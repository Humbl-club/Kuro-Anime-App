import Foundation

// MARK: - Discover lane rules (pure, testable)
// Small value rules the Discover, Search and Taste surfaces share. Nothing here performs I/O; the
// owner (`DiscoveryStore`) feeds them and the views render the result.

// MARK: Airing today

/// One title's airing slot as the catalogue states it (`anime.next_airing_at`,
/// `anime.next_episode_number`). Nothing here is estimated: a title without a stated time has no slot.
nonisolated struct DiscoverAiringSlot: Equatable, Sendable {
    let animeId: Int
    let airingAt: Date
    let episode: Int?
}

/// Orders the "Airing today" rail by air time without inventing one.
///
/// The `discover_bundle` rail is the anime whose `next_airing_at` falls on the current Berlin day,
/// ordered by popularity; its rows carry no time. The owner reads the stated times for those ids
/// separately. A stated time only counts when it lies on the same Berlin day as `now` (after an
/// episode airs the importer rolls `next_airing_at` a week forward, and that value is not today's
/// slot). Titles with a slot come first, earliest first; titles without one keep the server order.
nonisolated enum DiscoverAiringOrder {
    /// The day the rail is defined on (the bundle's `berlin_day_start` / `berlin_day_end`).
    static let railTimeZone = TimeZone(identifier: "Europe/Berlin") ?? .current

    /// `slot` when it is a slot of the rail's current day, otherwise nil.
    static func todaysSlot(_ slot: DiscoverAiringSlot?, now: Date, timeZone: TimeZone = railTimeZone) -> DiscoverAiringSlot? {
        guard let slot else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(slot.airingAt, inSameDayAs: now) ? slot : nil
    }

    /// The rail in air-time order: timed titles first (earliest first, ties by server position),
    /// then the untimed titles in server order.
    static func ordered<Item>(
        _ items: [Item],
        id: (Item) -> Int,
        slots: [Int: DiscoverAiringSlot],
        now: Date,
        timeZone: TimeZone = railTimeZone
    ) -> [Item] {
        let indexed = items.enumerated().map { (offset: $0.offset, item: $0.element) }
        let timed = indexed
            .compactMap { entry -> (offset: Int, item: Item, at: Date)? in
                guard let slot = todaysSlot(slots[id(entry.item)], now: now, timeZone: timeZone) else { return nil }
                return (entry.offset, entry.item, slot.airingAt)
            }
            .sorted { lhs, rhs in
                lhs.at == rhs.at ? lhs.offset < rhs.offset : lhs.at < rhs.at
            }
        let timedOffsets = Set(timed.map(\.offset))
        let untimed = indexed.filter { !timedOffsets.contains($0.offset) }
        return timed.map(\.item) + untimed.map(\.item)
    }
}

// MARK: Recent searches

/// The recent-search list of one account on this device: newest first, case-insensitively unique,
/// at most `capacity` entries, never shorter than two characters (the search threshold).
nonisolated struct RecentSearchList: Equatable, Sendable {
    static let capacity = 8
    static let minimumLength = 2

    private(set) var queries: [String]

    init(_ queries: [String] = []) {
        var list: [String] = []
        for query in queries {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= Self.minimumLength,
                  !list.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { continue }
            list.append(trimmed)
            if list.count == Self.capacity { break }
        }
        self.queries = list
    }

    /// Moves `query` to the front (replacing an earlier spelling of the same words).
    mutating func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumLength else { return }
        queries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        queries.insert(trimmed, at: 0)
        if queries.count > Self.capacity {
            queries.removeLast(queries.count - Self.capacity)
        }
    }

    mutating func remove(_ query: String) {
        queries.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
    }

    /// The device storage key of one account's list (lower-cased user id; nil when signed out).
    static func storageKey(userId: String?) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return "kuro.search.recent.\(userId.lowercased())"
    }
}

// MARK: Transport

/// Whether a failure proves the request never reached the server, so repeating it cannot repeat a
/// server-side write (`discover_bundle` records rail impressions). Timeouts and lost connections
/// are excluded: the server may already have run the call.
nonisolated enum DiscoveryTransport {
    static func failedBeforeSending(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed, .callIsActive:
            return true
        default:
            return false
        }
    }
}
