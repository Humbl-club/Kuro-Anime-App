import Foundation
import KuroCore

// MARK: - Release notification plan (pure)
// Which LOCAL notifications the account's release schedule asks for (spec D10 certainty rules):
//   - only titles the account is watching / reading (and has not muted on the detail page);
//   - only `confirmed` and `announced` rows; an `estimated` row NEVER notifies;
//   - precision `instant`: at the release moment, the body may show the time;
//   - precision `day`: 09:00 local on the release day (the day read exactly as `ReleaseCopy` reads it,
//     so a day stored at 00:00 UTC is never a day early west of UTC), day wording, no time;
//   - month / quarter / year windows and undated rows: no notification (there is no day to name);
//   - nothing in the past, soonest first, at most `limit` (iOS keeps 64 pending per app).
// Copy is `ReleaseCopy` rendered AT the fire moment ("Ep. 8 · Today, 21:30" / "Kap. 68 · Heute").
// Identifiers are stable per unit, so a re-plan replaces instead of duplicating. An AniList-confirmed
// anime episode uses the existing `airing-<id>-start` id (the reminder the airing path schedules for
// the same moment), so the two paths never notify twice.

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
    /// Hour of the morning-of-day notification for a release known only to the day.
    static let morningHour = 9
    /// A fire moment closer than this is skipped (it would arrive as stale news).
    static let minimumLead: TimeInterval = 60
    /// Identifier prefix of the release notifications (cleared with the airing reminders).
    static let identifierPrefix = "release-"

    static func plan(
        items: [ReleaseScheduleItem],
        following: Set<MediaKey>,
        muted: Set<MediaKey>,
        now: Date,
        german: Bool,
        locale: Locale,
        timeZone: TimeZone,
        limit: Int = maxPending
    ) -> [PlannedReleaseNotification] {
        guard limit > 0 else { return [] }
        let reader = ReleaseCopy(now: now, german: german, locale: locale, timeZone: timeZone)
        var seen = Set<String>()
        var planned: [PlannedReleaseNotification] = []
        for item in items {
            guard following.contains(item.key), !muted.contains(item.key),
                  let fire = fireDate(item, reader: reader), fire.timeIntervalSince(now) >= minimumLead else { continue }
            let id = identifier(item)
            guard seen.insert(id).inserted else { continue }
            let copy = ReleaseCopy(now: fire, german: german, locale: locale, timeZone: timeZone)
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            planned.append(PlannedReleaseNotification(
                id: id, key: item.key, title: title.isEmpty ? "Kuro" : title, body: copy.line(item), fireDate: fire,
                userInfo: ReleaseNotificationLink.userInfo(for: item.key)))
        }
        return Array(planned.sorted { lhs, rhs in
            lhs.fireDate != rhs.fireDate ? lhs.fireDate < rhs.fireDate : lhs.id < rhs.id
        }.prefix(limit))
    }

    /// When `item` notifies, or nil when it never does (estimate, window, undated, past, hidden).
    static func fireDate(_ item: ReleaseScheduleItem, reader: ReleaseCopy) -> Date? {
        guard item.basis != .estimated, item.isDisplayable, !item.isPast, let at = item.releaseAt else { return nil }
        switch item.effectivePrecision {
        case .instant:
            return item.showsTime ? at : nil
        case .day:
            guard let day = reader.calendarDay(item), let year = day.year, let month = day.month, let date = day.day else {
                return nil
            }
            let calendar = KuroLocale.calendar(locale: reader.locale, timeZone: reader.timeZone)
            return calendar.date(from: DateComponents(year: year, month: month, day: date, hour: morningHour))
        case .month, .quarter, .year:
            return nil
        }
    }

    /// Stable id per announced unit (see the file header for the AniList airing case).
    static func identifier(_ item: ReleaseScheduleItem) -> String {
        if item.medium == .anime, item.unitKind == .episode, item.basis == .confirmed,
           item.effectivePrecision == .instant, item.source.lowercased() == "anilist" {
            return "airing-\(item.mediaId)-start"
        }
        let unit = item.wholeUnitNumber.map(String.init)
            ?? item.unitNumber.map { String($0).replacingOccurrences(of: ".", with: "_") } ?? "next"
        return "\(identifierPrefix)\(item.medium.rawValue)-\(item.mediaId)-\(item.unitKind.rawValue)-\(unit)"
    }
}
