import CryptoKit
import Foundation
import KuroCore
import KuroLibrary

#if canImport(Supabase)

// MARK: - Series grouping state (W6)
// Collection shows one row per reviewed series. This extension holds the owner state: the per-account
// "Group seasons" switch (device preference, default on), the memoised rows built from the WHOLE Library
// (never the paged feed: a member may sit on an unloaded page or in another strip), the off-feed member
// card cache and the preparation read. Grouping is display only: no entry, id or status changes.
//
// Release switch `collection_series_grouping_v1` (default 0 %): checked BEFORE any request. While it is
// off there is no membership read, no member-card read, no `.added` follow-up read, no switch and no
// grouping. Every read that sends account library ids runs inside a credential lease of the account
// captured at the start, and publishes only while that context is current.

@MainActor
extension CollectionStore {
    /// "kuro.collection.groupSeasons." + the first 16 hex of SHA-256(lower-cased user id).
    nonisolated static func groupSeasonsKey(userId: String) -> String {
        let digest = SHA256.hash(data: Data(userId.lowercased().utf8))
        return "kuro.collection.groupSeasons." + digest.map { String(format: "%02x", $0) }.joined().prefix(16)
    }

    /// The release switch is on and the view is not the imported-titles subset.
    var isSeriesGroupingAvailable: Bool { groupingEnabled() && importedTitleKeys == nil }

    /// The current account's "Group seasons" choice (default on). Read from the device store on every
    /// access, so another account on the phone can never see this account's choice; `groupSeasonsRevision`
    /// makes the read observable.
    var groupSeasonsByAccount: Bool {
        _ = groupSeasonsRevision
        guard let userId = accountSession.current?.userId else { return true }
        return userDefaults.object(forKey: Self.groupSeasonsKey(userId: userId)) as? Bool ?? true
    }

    var groupsSeasons: Bool { isSeriesGroupingAvailable && groupSeasonsByAccount }

    /// Writes the current account's choice; a no-op signed out.
    func setGroupsSeasons(_ on: Bool) {
        guard let userId = accountSession.current?.userId else { return }
        userDefaults.set(on, forKey: Self.groupSeasonsKey(userId: userId))
        groupSeasonsRevision += 1
    }

    /// Rows of `medium` (groups + singles, anchor-ordered) when grouping is on, else one row per entry.
    func seriesRows(medium: MediaKind) -> [SeriesListRow] {
        guard groupsSeasons else { return SeriesListGrouping.rows(entriesOf(medium), membership: [:], enabled: false) }
        return groupedRows(medium: medium)
    }

    func seriesIndex(medium: MediaKind) -> SeriesListIndex {
        SeriesListIndex(rows: groupsSeasons ? groupedRows(medium: medium) : [])
    }

    /// True when the Library holds at least one reviewed group of two or more members.
    func hasSeriesGroups(medium: MediaKind) -> Bool {
        isSeriesGroupingAvailable && groupedRows(medium: medium).contains { $0.isGroup }
    }

    /// The reviewed membership the rows were built from (empty until a read answered).
    var seriesMembershipMap: [MediaKey: SeriesMembership] { catalog?.seriesMembershipMap ?? [:] }

    func memberMedia(_ key: MediaKey) -> Media? {
        if let media = collectionFeedItems.first(where: { $0.kind == key.kind && $0.id == key.id }) { return media }
        return seriesMemberMedia[key]
    }

    /// Reads reviewed membership for the Library's keys of `medium`, then the cards of members of
    /// multi-member groups that are neither on the loaded feed nor cached. Returns without any request
    /// when the release switch is off, the view is imported, or no account is signed in.
    func prepareSeriesGrouping(medium: MediaKind, loadedFeed: Set<MediaKey>) async {
        guard isSeriesGroupingAvailable, let account = accountSession.current,
              let catalog, let library else { return }
        let keys = library.allEntries.filter { $0.key.kind == medium }.map(\.key)
        guard !keys.isEmpty else { return }
        let generation = seriesPrepareGeneration
        do {
            try await accountSession.withCredentialLease(for: account) {
                await catalog.loadSeriesMembership(for: keys)
                guard !Task.isCancelled else { return }
                let missing = self.groupedRows(medium: medium).filter(\.isGroup).flatMap(\.members).map(\.key)
                    .filter { !loadedFeed.contains($0) && self.seriesMemberMedia[$0] == nil }
                let cards = await self.fetchMemberCards(missing)
                guard !Task.isCancelled, self.accountSession.isCurrent(account),
                      generation == self.seriesPrepareGeneration else { return }
                for card in cards { self.seriesMemberMedia[MediaKey(kind: card.kind, id: card.id)] = card }
            }
        } catch {
            // A refused, revoked or cancelled lease ends the preparation silently.
        }
    }

    /// After a title is added its membership is read once (inside a lease of the change's account).
    func startSeriesMembershipRead(for change: LibraryChange) {
        guard groupingEnabled(), change.kind == .added, importedTitleKeys == nil, let catalog else { return }
        let account = change.account
        let key = change.key
        seriesChangeTask?.cancel()
        seriesChangeTask = Task { [weak self] in
            guard let self else { return }
            try? await self.accountSession.withCredentialLease(for: account) {
                await catalog.loadSeriesMembership(for: [key])
            }
        }
    }

    // MARK: Internals

    private func entriesOf(_ medium: MediaKind) -> [LibraryEntry] {
        (library?.allEntries ?? []).filter { $0.key.kind == medium }
    }

    private func groupedRows(medium: MediaKind) -> [SeriesListRow] {
        let entries = entriesOf(medium)
        let version = catalog?.seriesMembershipVersion ?? 0
        if let memo = seriesRowsMemo, memo.medium == medium, memo.version == version, memo.entries == entries {
            return memo.rows
        }
        let rows = SeriesListGrouping.rows(entries, membership: catalog?.seriesMembershipMap ?? [:])
        seriesRowsMemo = (medium, version, entries, rows)
        return rows
    }

    /// Public catalogue cards of off-feed members, 100 per batch (the catalogue's own card cache and
    /// batching), converted to display models.
    private func fetchMemberCards(_ keys: [MediaKey]) async -> [Media] {
        guard let catalog, !keys.isEmpty else { return [] }
        var out: [Media] = []
        let anime = keys.filter { $0.kind == .anime }.map(\.id)
        let manga = keys.filter { $0.kind == .manga }.map(\.id)
        if !anime.isEmpty, let rows = await catalog.fetchAnimeByIdsPreservingOrder(anime) {
            out += rows.map(Self.media(from:))
        }
        if !manga.isEmpty, let rows = await catalog.fetchMangaByIdsPreservingOrder(manga) {
            out += rows.map(Self.media(from:))
        }
        return out
    }

    private nonisolated static func media(from item: some MediaDisplayable) -> Media {
        Media(id: item.id, kind: item.kind, title: item.title, imageURL: item.imageURL, year: item.year,
              displayDescription: item.displayDescription, episodes: item.episodes, chapters: item.chapters,
              rating: item.rating, genres: item.genres, statusRaw: item.statusRaw, formatRaw: item.formatRaw,
              popularityValue: item.popularityValue, trendingValue: item.trendingValue,
              createdAtValue: item.createdAtValue)
    }
}

#endif
