import Foundation
import KuroCore
import KuroLibrary

#if canImport(Supabase)

// MARK: - Release alert offer (W3a; state in ReleasesStore; pure decision in ReleaseAlertOffer.swift)
// Raised from the Library change sink after a save puts an airing title on Watching / Rewatching, from
// data already on the device only: it sends NO request of its own. The release comes from
// `nextRelease`, a fresh cached `mediaSchedule` answer, or (a brand-new anime) the `user_airing_next`
// refresh `libraryDidChange` already starts, awaited here once within `ReleaseAlertOfferPolicy.window`.
// Nothing here ever prompts: only `acceptAlertOffer` reaches the bell's call (D14).

@MainActor
extension ReleasesStore {
    /// `nextRelease` first, then a fresh cached per-title answer. Never requests.
    func knownRelease(for key: MediaKey, now: Date = Date()) -> ReleaseScheduleItem? {
        nextRelease(for: key, now: now) ?? cachedMediaRelease(for: key, now: now)
    }

    /// A change that entered Watching / Rewatching may raise an offer (newest wins). Called by
    /// `libraryDidChange`; import publication, realtime and launch never reach a sink, so they raise none.
    func considerAlertOffer(_ change: LibraryChange, now: Date = Date()) {
        guard accountSession.isCurrent(change.account),
              ReleaseAlertOfferPolicy.entersFollowed(previous: change.previous?.status, current: change.current?.status)
        else { return }
        // Read now: a batch scope may have ended by the time a spawned task runs.
        let suppressed = alertOfferSuppression > 0
        guard !suppressed else { return }
        let context = change.account
        let key = change.key
        let previous = change.previous?.status, status = change.current?.status
        let followUp = libraryChangeTask
        alertOfferTask?.cancel()
        alertOfferTask = Task { [weak self] in
            guard let self else { return }
            let permission = await self.reminders.notificationPermission()
            guard !Task.isCancelled, self.accountSession.isCurrent(context) else { return }
            var next = self.knownRelease(for: key)
            if next == nil, key.kind == .anime, let followUp {
                // The existing upcoming refresh for an added anime; evaluate once after it.
                await followUp.value
                guard !Task.isCancelled, self.accountSession.isCurrent(context),
                      Date() < now.addingTimeInterval(ReleaseAlertOfferPolicy.window) else { return }
                next = self.knownRelease(for: key)
            }
            guard let next, !Task.isCancelled, self.accountSession.isCurrent(context) else { return }
            let input = ReleaseAlertOfferPolicy.Input(
                previousStatus: previous, status: status, next: next,
                toggleOn: self.reminders.releaseNotificationPreference(for: context) == true,
                permission: permission,
                allowed: self.reminders.allowedReleaseNotificationKeys(for: context),
                muted: self.reminders.mutedReleaseNotificationKeys(for: context),
                offered: self.reminders.offeredAlertKeys(for: context),
                declined: self.reminders.declinedAlertKeys(for: context),
                suppressed: false)
            guard ReleaseAlertOfferPolicy.shouldOffer(input, key: key, now: Date()) else { return }
            self.pendingAlertOffer = ReleaseAlertOffer(id: UUID(), key: key, item: next, accountUserId: context.userId, createdAt: Date())
            self.alertOfferBoundHost = nil
        }
    }

    /// Runs `work` (a batch status change, the widget's queued +1) with no offers raised: no save
    /// confirmation is on screen for those writes.
    func withAlertOffersSuppressed<T>(_ work: () async -> T) async -> T {
        alertOfferSuppression += 1
        defer { alertOfferSuppression = max(0, alertOfferSuppression - 1) }
        return await work()
    }

    /// The first host to draw the pending offer binds it (and the title counts as offered, once). Ignored
    /// for another offer, another account, or when another host is already bound.
    func alertOfferPresented(_ offerId: UUID, by hostId: UUID) {
        guard let offer = pendingAlertOffer, offer.id == offerId,
              alertOfferBoundHost == nil || alertOfferBoundHost == hostId,
              let context = accountSession.current,
              AccountSessionCoordinator.sameUser(context.userId, offer.accountUserId) else { return }
        alertOfferBoundHost = hostId
        reminders.noteAlertOffered(offer.key, for: context)
    }

    /// The pending offer when `offerId` matches and the current account is the one it was raised for.
    private func ownedAlertOffer(_ offerId: UUID) -> (offer: ReleaseAlertOffer, context: AccountContext)? {
        guard let offer = pendingAlertOffer, offer.id == offerId, let context = accountSession.current,
              AccountSessionCoordinator.sameUser(context.userId, offer.accountUserId) else { return nil }
        return (offer, context)
    }

    /// "Notify me": the detail bell's own call for the offer's title, the one path from the offer to a
    /// permission prompt. nil: no such offer, or another account is current (nothing is written).
    func acceptAlertOffer(_ offerId: UUID) async -> ReleaseNotificationToggleResult? {
        guard let owned = ownedAlertOffer(offerId) else { return nil }
        pendingAlertOffer = nil
        alertOfferBoundHost = nil
        return await setReleaseNotification(true, for: owned.offer.key)
    }

    /// "Not now": the title counts toward the account's three declines.
    func declineAlertOffer(_ offerId: UUID) {
        guard let owned = ownedAlertOffer(offerId) else { return }
        pendingAlertOffer = nil
        alertOfferBoundHost = nil
        reminders.noteAlertDeclined(owned.offer.key, for: owned.context)
    }

    /// The hold elapsed in the bound host: the offer goes. NOT a decline. Ignored from any other host.
    func expireAlertOffer(_ offerId: UUID, by hostId: UUID) {
        guard let offer = pendingAlertOffer, offer.id == offerId, alertOfferBoundHost == hostId else { return }
        pendingAlertOffer = nil
        alertOfferBoundHost = nil
    }
}
#endif
