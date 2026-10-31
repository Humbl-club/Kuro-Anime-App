import Foundation
import KuroCore
import KuroLibrary

#if canImport(Supabase)
import Supabase

extension CollectionStore {
    /// This is a temporary selection over Library, never a second tracking list.
    func showImportedTitles(_ keys: Set<MediaKey>) {
        guard let context = accountSession.current else { return }
        importedAccount = context; importedTitleKeys = keys
        importedGeneration += 1; importedMedia = []; importedOffset = 0; importedHasMore = !keys.isEmpty
        importedLoadTask?.cancel()
    }

    func clearImportedTitles() {
        importedGeneration += 1; importedLoadTask?.cancel(); importedLoadTask = nil
        importedTitleKeys = nil; importedAccount = nil; importedMedia = []; importedOffset = 0; importedHasMore = false
    }

    var displayedFeedItems: [Media] {
        guard let keys = importedTitleKeys else { return collectionFeedItems }
        guard accountSession.isCurrent(importedAccount) else { return [] }
        return importedMedia.filter { keys.contains($0.libraryKey) && library?.entry(for: $0.libraryKey) != nil }
    }

    var displayedSeriesGroups: [CollectionSeriesGroup] {
        guard importedTitleKeys != nil else { return seriesGroups }
        return displayedFeedItems.compactMap { media in
            guard let row = library?.entry(for: media.libraryKey), let revision = row.revision,
                  let lifecycle = row.lifecycleId else { return nil }
            let child = CollectionSeriesChild(mediaId: media.id,
                listType: dbListType(for: row.status, mediaType: media.kind.rawValue), progress: row.progress,
                serverRevision: revision, lifecycleId: lifecycle.uuidString, title: media.title, mediaKind: media.kind)
            return CollectionSeriesGroup(groupKey: "imported:\(media.kind.rawValue):\(media.id)",
                updatedAt: ISO8601DateFormatter().string(from: row.updatedAt), children: [child],
                childCount: 1, childrenNext: nil)
        }
    }

    var displayedSeriesNextCursor: String? {
        importedTitleKeys == nil ? seriesNextCursor : (importedHasMore ? String(importedOffset) : nil)
    }
    var hasMoreDisplayedFeed: Bool { importedTitleKeys == nil ? hasMoreCollectionFeed : importedHasMore }

    private struct ImportedCatalogRow: Decodable {
        let id: Int
        let title_english: String?
        let title_romaji: String?
        let title_native: String?
        let cover_image_large: String?
        let banner_image: String?
        func media(kind: MediaKind) -> Media {
            Media(id: id, kind: kind, title: title_english ?? title_romaji ?? title_native ?? "Untitled \(kind.rawValue.lowercased()) #\(id)",
                imageURL: cover_image_large, year: "", displayDescription: "", episodes: nil, chapters: nil,
                rating: nil, genres: nil, statusRaw: nil, formatRaw: nil, popularityValue: nil,
                trendingValue: nil, createdAtValue: nil)
        }
    }

    /// Public catalog hydration is bounded to thirty selected canonical rows per deliberate page.
    func fetchImportedTitles(medium: String?, reset: Bool) async {
        guard let context = importedAccount, accountSession.isCurrent(context), let keys = importedTitleKeys,
              let library else { return }
        if !reset && !importedHasMore { return }
        importedGeneration += 1
        let generation = importedGeneration
        let selected = keys.filter { key in
            medium == nil || key.kind.rawValue.lowercased() == medium
        }.sorted { $0.kind.rawValue == $1.kind.rawValue ? $0.id < $1.id : $0.kind.rawValue < $1.kind.rawValue }
        let offset = reset ? 0 : importedOffset
        let page = Array(selected.dropFirst(offset).prefix(30))
        isCollectionLoading = reset; isLoadingMoreCollectionFeed = !reset; collectionErrorMessage = nil
        defer {
            if generation == importedGeneration, accountSession.isCurrent(context) {
                isCollectionLoading = false; isLoadingMoreCollectionFeed = false
            }
        }
        do {
            let client = try requiredClient()
            var result: [Media] = []
            for kind in [MediaKind.anime, .manga] {
                let ids = page.filter { $0.kind == kind && library.entry(for: $0) != nil }.map(\.id)
                if ids.isEmpty { continue }
                let rows: [ImportedCatalogRow] = try await accountSession.withCredentialLease(for: context) {
                    try await client.from(kind == .anime ? "anime" : "manga")
                        .select("id,title_english,title_romaji,title_native,cover_image_large,banner_image")
                        .in("id", values: ids).limit(30).execute().value
                }
                guard generation == importedGeneration, accountSession.isCurrent(context), !Task.isCancelled else { return }
                result += rows.map { $0.media(kind: kind) }
            }
            guard generation == importedGeneration, accountSession.isCurrent(context) else { return }
            if reset { importedMedia = [] }
            importedMedia += result.filter { media in !importedMedia.contains(where: { $0.libraryKey == media.libraryKey }) }
            importedOffset = offset + page.count; importedHasMore = importedOffset < selected.count
        } catch {
            guard generation == importedGeneration, accountSession.isCurrent(context) else { return }
            collectionErrorMessage = "Imported titles could not be loaded. Try again."
        }
    }
}
#endif
