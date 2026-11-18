import Foundation
import KuroCore
import KuroLibrary

// MARK: - Release alert offer (W3a, pure)
// After a save puts an airing title on Watching / Rewatching, the confirmation the user is looking at
// may offer "Notify me when episode N airs". This file holds the model, the decision and the copy; it
// reads nothing and requests nothing. The decision only uses data already on the device (the planner's
// own `isEligible` gate, so an offer implies the planner would notify once the bell is on). Only the
// tap on "Notify me" reaches the bell's call (`ReleasesStore.setReleaseNotification`), the one place
// that may prompt for permission (D14).

nonisolated struct ReleaseAlertOffer: Equatable, Sendable, Identifiable {
    let id: UUID
    let key: MediaKey
    let item: ReleaseScheduleItem
    /// The account the offer was raised for (an accept or decline for another account is refused).
    let accountUserId: String
    let createdAt: Date
}

nonisolated enum ReleaseAlertOfferPolicy {
    /// "Not now" on this many titles stops the offers for the account.
    static let declineLimit = 3
    /// The release must be known this soon after the save, or no offer is made.
    static let window: TimeInterval = 5
    /// How long the offer stays on screen without assistive technology.
    static let hold: TimeInterval = 10
    /// An offer no host drew by `createdAt + presentWithin` lapses unseen (not offered, not declined).
    static let presentWithin: TimeInterval = 30

    struct Input: Equatable, Sendable {
        var previousStatus: ListStatus?
        var status: ListStatus?
        var next: ReleaseScheduleItem?
        /// The account's stored Profile preference is on.
        var toggleOn: Bool
        var permission: NotificationPermission
        var allowed: Set<MediaKey>
        var muted: Set<MediaKey>
        var offered: Set<MediaKey>
        var declined: Set<MediaKey>
        /// A batch or widget writer is running: no confirmation is on screen for these saves.
        var suppressed: Bool
    }

    /// Pattern match: `NotificationPermission`'s `Equatable` is main-actor isolated, this enum is not.
    private static func isDenied(_ permission: NotificationPermission) -> Bool {
        if case .denied = permission { return true }
        return false
    }

    private static func isFollowed(_ status: ListStatus?) -> Bool {
        status == .current || status == .repeating
    }

    /// The status entered the followed set (`.current` / `.repeating`) with this change. A Planning
    /// title never notifies (D14), so an offer for it would promise nothing.
    static func entersFollowed(previous: ListStatus?, current: ListStatus?) -> Bool {
        isFollowed(current) && !isFollowed(previous)
    }

    static func shouldOffer(_ input: Input, key: MediaKey, now: Date) -> Bool {
        guard entersFollowed(previous: input.previousStatus, current: input.status),
              let next = input.next, next.key == key,
              ReleaseNotificationPlanner.isEligible(next, now: now),
              !input.toggleOn,
              !Self.isDenied(input.permission),
              !input.allowed.contains(key), !input.muted.contains(key),
              !input.offered.contains(key),
              input.declined.count < declineLimit,
              !input.suppressed else { return false }
        return true
    }

    /// Unbound and older than `presentWithin`: dropped unseen.
    static func hasLapsed(_ offer: ReleaseAlertOffer, boundHost: UUID?, now: Date) -> Bool {
        boundHost == nil && now.timeIntervalSince(offer.createdAt) >= presentWithin
    }
}

nonisolated enum ReleaseAlertOfferCopy {
    static func prompt(_ item: ReleaseScheduleItem, german: Bool) -> String {
        if let number = item.wholeUnitNumber {
            switch item.unitKind {
            case .episode, .season:
                return german ? "Benachrichtigen, wenn Folge \(number) läuft" : "Notify me when episode \(number) airs"
            case .chapter:
                return german ? "Benachrichtigen, wenn Kapitel \(number) erscheint" : "Notify me when chapter \(number) is out"
            case .volume:
                return german ? "Benachrichtigen, wenn Band \(number) erscheint" : "Notify me when volume \(number) is out"
            }
        }
        switch item.unitKind {
        case .episode, .season:
            return german ? "Benachrichtigen, wenn die nächste Folge läuft" : "Notify me when the next episode airs"
        case .chapter:
            return german ? "Benachrichtigen, wenn das nächste Kapitel erscheint" : "Notify me when the next chapter is out"
        case .volume:
            return german ? "Benachrichtigen, wenn der nächste Band erscheint" : "Notify me when the next volume is out"
        }
    }

    static func notifyMe(german: Bool) -> String { german ? "Benachrichtigen" : "Notify me" }
    static func notNow(german: Bool) -> String { german ? "Nicht jetzt" : "Not now" }
    static func saved(german: Bool) -> String { german ? "Gespeichert." : "Saved." }
}
