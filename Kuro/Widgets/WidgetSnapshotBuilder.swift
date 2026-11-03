import Foundation
import KuroCore
import KuroLibrary
import KuroWidgetSupport

// MARK: - Widget snapshot builder (pure)
// Turns the current account's release schedule, its watching/reading rows and the titles' catalogue
// metadata into the `WidgetSnapshot` the extension renders. Every certainty-dependent string comes
// from `ReleaseCopy` (spec D10: a time of day only for an instant that is not an estimate, estimates
// say "expected"), and `countdownTarget` is set only when `ReleaseScheduleItem.showsTime` allows a
// time, so the extension can never show a clock time for an announced day, a window or an estimate.
// Everything is explicit (now, language, zone), so tests pin it.

/// One Library row the snapshot may list under Now Watching.
nonisolated struct WidgetTrackedTitle: Equatable, Sendable {
    let key: MediaKey
    let status: ListStatus
    /// The displayed position (pending outbox writes included).
    let progress: Int
    let lifecycleId: UUID?
    let revision: Int64?
    let updatedAt: Date
}

/// Catalogue facts of one title (public data).
nonisolated struct WidgetTitleMetadata: Equatable, Sendable {
    let title: String
    /// Episodes (anime) / chapters (manga) when known.
    let total: Int?
    let artworkURL: URL?
}

nonisolated enum WidgetSnapshotBuilder {
    /// Statuses listed under Now Watching (watching / reading, rewatching / rereading).
    static let nowWatchingStatuses: Set<ListStatus> = [.current, .repeating]

    static func build(
        account: WidgetAccountHash,
        now: Date,
        copy: ReleaseCopy,
        releases: [ReleaseScheduleItem],
        tracked: [WidgetTrackedTitle],
        metadata: [MediaKey: WidgetTitleMetadata],
        thumbnails: [MediaKey: String]
    ) -> WidgetSnapshot {
        let releaseRows = releases
            .filter { copy.isAhead($0) }
            .prefix(WidgetSnapshot.maxReleases)
            .map { releaseItem($0, copy: copy, metadata: metadata[$0.key], thumbnail: thumbnails[$0.key]) }
        let watching = nowWatchingRows(tracked: tracked, metadata: metadata, releases: releases,
                                       copy: copy, thumbnails: thumbnails)
        return WidgetSnapshot(account: account, generatedAt: now, german: copy.german,
                              releases: Array(releaseRows), nowWatching: watching)
    }

    /// The Now Watching rows: watching/reading titles with a known name, most recently updated first.
    static func nowWatchingRows(tracked: [WidgetTrackedTitle], metadata: [MediaKey: WidgetTitleMetadata],
                                releases: [ReleaseScheduleItem], copy: ReleaseCopy,
                                thumbnails: [MediaKey: String]) -> [WidgetNowWatchingItem] {
        let releaseTitles = Dictionary(releases.map { ($0.key, $0.title) }, uniquingKeysWith: { first, _ in first })
        return tracked
            .filter { nowWatchingStatuses.contains($0.status) }
            .sorted { lhs, rhs in
                lhs.updatedAt != rhs.updatedAt ? lhs.updatedAt > rhs.updatedAt : lhs.key.id < rhs.key.id
            }
            .compactMap { row -> WidgetNowWatchingItem? in
                let facts = metadata[row.key]
                let name = (facts?.title ?? releaseTitles[row.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return WidgetNowWatchingItem(
                    medium: row.key.kind, mediaId: row.key.id, title: name, progress: max(0, row.progress),
                    total: facts?.total.flatMap { $0 > 0 ? $0 : nil },
                    unitPrefix: unitPrefix(row.key.kind, german: copy.german),
                    lifecycleId: row.lifecycleId?.uuidString, revision: row.revision,
                    artworkURL: facts?.artworkURL, thumbnail: thumbnails[row.key],
                    deepLink: deepLink(row.key))
            }
            .prefix(WidgetSnapshot.maxNowWatching)
            .map { $0 }
    }

    static func releaseItem(_ item: ReleaseScheduleItem, copy: ReleaseCopy, metadata: WidgetTitleMetadata?,
                            thumbnail: String?) -> WidgetReleaseItem {
        let title = item.title.isEmpty ? (metadata?.title ?? "") : item.title
        return WidgetReleaseItem(
            id: item.id, medium: item.medium, mediaId: item.mediaId, title: title,
            unitLabel: copy.unitLabel(item), datePhrase: copy.datePhrase(item),
            line: copy.line(item, undatedFallback: true), accessibilityLine: copy.accessibilityLine(item),
            basis: item.basis.rawValue, precision: item.effectivePrecision.rawValue,
            countdownTarget: item.showsTime ? item.releaseAt : nil,
            expiresAt: expiry(item, copy: copy), isEstimate: item.basis == .estimated,
            thumbnail: thumbnail, deepLink: deepLink(item.key))
    }

    /// When the row stops being upcoming: an instant at its moment, a day at the reader's next local
    /// midnight after that day; windows and undated rows have no expiry here.
    static func expiry(_ item: ReleaseScheduleItem, copy: ReleaseCopy) -> Date? {
        guard let at = item.releaseAt else { return nil }
        switch item.effectivePrecision {
        case .instant: return at
        case .day:
            guard let day = copy.calendarDay(item), let year = day.year, let month = day.month, let date = day.day else {
                return nil
            }
            let calendar = KuroLocale.calendar(locale: copy.locale, timeZone: copy.timeZone)
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: date)) else { return nil }
            return calendar.date(byAdding: .day, value: 1, to: start)
        case .month, .quarter, .year: return nil
        }
    }

    /// "Ep. " / "F. ", "Ch. " / "Kap. " (the `ReleaseCopy.unitLabel` prefixes).
    static func unitPrefix(_ kind: MediaKind, german: Bool) -> String {
        switch kind {
        case .anime: return german ? "F. " : "Ep. "
        case .manga: return german ? "Kap. " : "Ch. "
        }
    }

    /// The title journey (`DeepLink.anime` / `.manga`): navigation only.
    static func deepLink(_ key: MediaKey) -> URL? {
        URL(string: "kuro://\(key.kind.rawValue)/\(key.id)")
    }

    /// Only http(s) artwork with a host (no `file:`/app schemes from data).
    static func httpsURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Titles whose thumbnail the snapshot would show (Now Watching first, then releases).
    static func artworkNeeded(tracked: [WidgetTrackedTitle], releases: [ReleaseScheduleItem],
                              metadata: [MediaKey: WidgetTitleMetadata], copy: ReleaseCopy) -> [(MediaKey, URL)] {
        var seen = Set<MediaKey>()
        var result: [(MediaKey, URL)] = []
        let watching = tracked.filter { nowWatchingStatuses.contains($0.status) }
            .sorted { $0.updatedAt > $1.updatedAt }.prefix(WidgetSnapshot.maxNowWatching).map(\.key)
        let upcoming = releases.filter { copy.isAhead($0) }.prefix(WidgetSnapshot.maxReleases)
        for key in watching {
            guard seen.insert(key).inserted, let url = metadata[key]?.artworkURL else { continue }
            result.append((key, url))
        }
        for item in upcoming {
            guard seen.insert(item.key).inserted else { continue }
            let url = item.coverImage.flatMap(httpsURL) ?? metadata[item.key]?.artworkURL
            if let url { result.append((item.key, url)) }
        }
        return result
    }
}
