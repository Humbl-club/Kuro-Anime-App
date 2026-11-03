import Foundation
import KuroCore
import KuroLibrary

#if canImport(Supabase)

// MARK: - Release notifications (view-facing API; state in ReleasesStore; spec D14, §11)
// Profile toggle and detail bell call these; nothing else may ask for notification permission.
// Default OFF. The Profile toggle turns on every watching / reading title; a detail bell turns one
// title on (even while the toggle is off) or mutes it. The plan (`ReleaseNotificationPlanner`) is
// rebuilt from the account's loaded schedule and its rows whenever either changes (debounced) and on
// every foreground, and committed on the reminder chain (`ReminderScheduler.syncReleaseNotifications`).
// Only exact, non-estimate confirmed / announced times notify, at their moment. Everything is cleared
// on sign-out / account switch (the session funnel's reminder removal covers `release-*`).

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

    /// Whether `key` notifies for the current account (detail bell state): a bell override first,
    /// then the Profile toggle (spec §11.2 `override[key] ?? followed`).
    func releaseNotificationsOn(for key: MediaKey) -> Bool {
        guard notificationPermission == .authorized else { return false }
        if allowedReleaseNotificationKeys.contains(key) { return true }
        return releaseNotificationsEnabled && !mutedReleaseNotificationKeys.contains(key)
    }

    /// Whether anything can notify for the current account (toggle on, or a bell turned a title on).
    var releaseNotificationsActive: Bool {
        notificationPermission == .authorized && (releaseNotificationsEnabled || !allowedReleaseNotificationKeys.isEmpty)
    }

    // MARK: Explicit user actions (the only permission requests)

    /// The Profile toggle. On: asks for permission (the system prompt appears only while undecided),
    /// stores the choice and schedules the account's plan. Off: stores the choice; titles a bell
    /// turned on keep notifying, everything else pending is removed.
    @discardableResult
    func setReleaseNotificationsEnabled(_ enabled: Bool) async -> ReleaseNotificationToggleResult {
        guard let context = accountSession.current else { return .signedOut }
        guard enabled else {
            reminders.setReleaseNotificationPreference(false, for: context)
            releaseNotificationsEnabled = false
            releaseNotificationTask?.cancel()
            if allowedReleaseNotificationKeys.isEmpty {
                hasCommittedReleaseNotifications = false
                await reminders.removeAllReleaseNotifications().value
            } else {
                await syncReleaseNotificationsNow()
            }
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

    /// The detail bell for one title (a per-title override, spec D14). On: asks for permission when it
    /// is undecided (an explicit action), then turns THIS title on; the Profile toggle is untouched.
    /// Off: mutes the title (its pending notifications go on the re-plan).
    @discardableResult
    func setReleaseNotification(_ enabled: Bool, for key: MediaKey) async -> ReleaseNotificationToggleResult {
        guard let context = accountSession.current else { return .signedOut }
        var muted = reminders.mutedReleaseNotificationKeys(for: context)
        var allowed = reminders.allowedReleaseNotificationKeys(for: context)
        if enabled {
            let permission = await reminders.requestNotificationPermission()
            guard accountSession.isCurrent(context) else { return .signedOut }
            notificationPermission = permission
            guard permission == .authorized else { return .permissionDenied }
            muted.remove(key)
            allowed.insert(key)
        } else {
            muted.insert(key)
            allowed.remove(key)
        }
        guard accountSession.isCurrent(context) else { return .signedOut }
        reminders.setMutedReleaseNotificationKeys(muted, for: context)
        reminders.setAllowedReleaseNotificationKeys(allowed, for: context)
        mutedReleaseNotificationKeys = muted
        allowedReleaseNotificationKeys = allowed
        // A title turned on should not stay silent because its schedule was never loaded.
        if enabled, scheduleCoverageByMedium.isEmpty { _ = await loadSchedule() }
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
        allowedReleaseNotificationKeys = reminders.allowedReleaseNotificationKeys(for: context)
        // Default off (spec D14): only an explicit Profile toggle turns every watched title on.
        releaseNotificationsEnabled = permission == .authorized && reminders.releaseNotificationPreference(for: context) == true
    }

    /// Foreground / bootstrap: state, then (when on) the schedule (cached 5 min) and the plan.
    func refreshReleaseNotifications() async {
        // The retired per-airing reminders leave the device once (spec §11.2), before any plan commit.
        await reminders.retireLegacyAiringRemindersOnce()?.value
        await refreshReleaseNotificationState()
        guard releaseNotificationsActive, accountSession.current != nil else { return }
        // Something is on explicitly, so the schedule is read even when no screen asked yet.
        if scheduleCoverageByMedium.isEmpty { _ = await loadSchedule() }
        await syncReleaseNotificationsNow()
    }

    /// Re-plans after `releaseNotificationDebounce` (a newer request replaces a waiting one).
    func scheduleReleaseNotificationsSoon() {
        guard releaseNotificationsActive || hasCommittedReleaseNotifications, accountSession.current != nil else { return }
        releaseNotificationTask?.cancel()
        releaseNotificationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.releaseNotificationDebounce)
            guard !Task.isCancelled else { return }
            await self?.syncReleaseNotificationsNow()
        }
    }

    /// The current plan for the account (pure inputs; tests read it).
    func plannedReleaseNotifications(now: Date = Date()) -> [PlannedReleaseNotification] {
        let watching = releaseNotificationsEnabled
            ? Set((library?.allEntries ?? []).filter { $0.status == .current || $0.status == .repeating }.map(\.key))
            : []
        let following = watching.union(allowedReleaseNotificationKeys)
        return ReleaseNotificationPlanner.plan(
            items: scheduleItems(for: nil, now: now), following: following, muted: mutedReleaseNotificationKeys,
            now: now, german: KuroLocale.isGerman, locale: KuroLocale.locale, timeZone: KuroLocale.timeZone)
    }

    /// Commits the current plan now (no-op when off or signed out).
    @discardableResult
    func syncReleaseNotificationsNow(now: Date = Date()) async -> ReminderScheduler.ReleaseSyncOutcome {
        guard let context = accountSession.current else { return .obsolete }
        guard releaseNotificationsActive else {
            // Nothing is on any more (or permission was revoked): what this account left pending goes.
            if hasCommittedReleaseNotifications {
                hasCommittedReleaseNotifications = false
                await reminders.removeAllReleaseNotifications().value
            }
            return .notAuthorized
        }
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
