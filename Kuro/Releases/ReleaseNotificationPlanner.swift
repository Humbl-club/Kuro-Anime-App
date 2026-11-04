import Foundation
import KuroCore

// MARK: - Release notification plan (pure; details-songs spec D14, §11.2)
// Which LOCAL notifications the account's release schedule asks for:
//   - only a row with an exact, non-estimate time (`item.showsTime`) whose basis is `confirmed` or
//     `announced` (`isEligible`): an estimate NEVER notifies, and neither does an announced DAY,
//     a month / quarter / year window or an undated row (owner choice §18.3);
//   - one notification at the release moment (the legacy "1 h before" reminder is retired);
//   - only titles that are on for the account (`following`, built by `ReleasesStore`) and not muted;
//   - per title its next two eligible rows, soonest first, at most `limit` (48) in total;
//   - nothing within `minimumLead` of now and nothing past.
// Copy is `ReleaseReminderCopy` (EN/DE, spec §11.3). Identifiers are stable per unit
// (`release-<medium>-<id>-<unitKind>-<unit>`), so a re-plan replaces instead of duplicating; none of
// them uses the legacy `airing-` prefix, which is removed once on first run.

nonisolated struct PlannedReleaseNotification: Equatable, Sendable, Identifiable {
    let id: String
    let key: MediaKey
    let title: String
    let body: String
    let fireDate: Date
    /// `["kuro_link": "kuro://anime/<id>"]`: the tap opens the title journey.
    let userInfo: [String: String]
}

nonisolated enum ReleaseNotificationPlanner {
    /// The system's pending-notification limit per app.
    static let maxPending = 64
    /// The plan's own cap (spec §11.2): leaves room under the system's 64.
    static let planLimit = 48
    /// Eligible rows planned per title.
    static let perTitle = 2
    /// A fire moment closer than this is skipped (it would arrive as stale news).
    static let minimumLead: TimeInterval = 60
    /// Identifier prefix of the release notifications.
    static let identifierPrefix = "release-"
    /// Prefix of the retired airing reminders ("… airs now" / "In 1 hour: …"), removed once.
    static let legacyAiringPrefix = "airing-"

    /// Spec §11.2 / §20: an exact, non-estimate time from a confirmed or announced source, more than
    /// `minimumLead` ahead and not past.
    static func isEligible(_ item: ReleaseScheduleItem, now: Date) -> Bool {
        guard item.showsTime, item.basis == .confirmed || item.basis == .announced,
              item.isDisplayable, !item.isPast, let at = item.releaseAt else { return false }
        return at.timeIntervalSince(now) > minimumLead
    }

    static func plan(
        items: [ReleaseScheduleItem],
        following: Set<MediaKey>,
        muted: Set<MediaKey>,
        now: Date,
        german: Bool,
        locale: Locale,
        timeZone: TimeZone,
        limit: Int = planLimit
    ) -> [PlannedReleaseNotification] {
        guard limit > 0 else { return [] }
        let eligible = items
            .filter { following.contains($0.key) && !muted.contains($0.key) && isEligible($0, now: now) }
            .sorted { lhs, rhs in
                let l = lhs.releaseAt ?? .distantFuture, r = rhs.releaseAt ?? .distantFuture
                return l != r ? l < r : identifier(lhs) < identifier(rhs)
            }
        var seen = Set<String>()
        var perKey: [MediaKey: Int] = [:]
        var planned: [PlannedReleaseNotification] = []
        for item in eligible {
            guard let fire = item.releaseAt, perKey[item.key, default: 0] < perTitle else { continue }
            let id = identifier(item)
            guard seen.insert(id).inserted else { continue }
            perKey[item.key, default: 0] += 1
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            planned.append(PlannedReleaseNotification(
                id: id, key: item.key, title: title.isEmpty ? "Kuro" : title,
                body: ReleaseReminderCopy.body(item, german: german), fireDate: fire,
                userInfo: ReleaseNotificationLink.userInfo(for: item.key)))
            if planned.count == limit { break }
        }
        return planned
    }

    /// When `item` notifies (its release moment), or nil when it never does.
    static func fireDate(_ item: ReleaseScheduleItem, now: Date) -> Date? {
        isEligible(item, now: now) ? item.releaseAt : nil
    }

    /// Stable id per announced unit.
    static func identifier(_ item: ReleaseScheduleItem) -> String {
        let unit = item.wholeUnitNumber.map(String.init)
            ?? item.unitNumber.map { String($0).replacingOccurrences(of: ".", with: "_") } ?? "next"
        return "\(identifierPrefix)\(item.medium.rawValue)-\(item.mediaId)-\(item.unitKind.rawValue)-\(unit)"
    }
}

/// Notification body copy (spec §11.3, EN/DE). No marketing line, no progress claim, no service.
nonisolated enum ReleaseReminderCopy {
    static func body(_ item: ReleaseScheduleItem, german: Bool) -> String {
        let number = item.wholeUnitNumber
        switch item.unitKind {
        case .episode:
            if let number { return german ? "Folge \(number) wurde gerade ausgestrahlt." : "Episode \(number) just aired." }
            return newEpisode(german)
        case .chapter:
            if let number { return german ? "Kapitel \(number) ist erschienen." : "Chapter \(number) is out." }
            return newChapter(german)
        case .volume:
            if let number { return german ? "Band \(number) ist erschienen." : "Volume \(number) is out." }
            return newChapter(german)
        case .season:
            return item.medium == .anime ? newEpisode(german) : newChapter(german)
        }
    }

    private static func newEpisode(_ german: Bool) -> String {
        german ? "Eine neue Folge wurde gerade ausgestrahlt." : "A new episode just aired."
    }

    private static func newChapter(_ german: Bool) -> String {
        german ? "Ein neues Kapitel ist erschienen." : "A new chapter is out."
    }
}
