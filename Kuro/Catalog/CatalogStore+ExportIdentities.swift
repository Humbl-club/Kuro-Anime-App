import Foundation
import KuroCore
import KuroLibrary

#if canImport(Supabase)
import Supabase

// MARK: - Export identities (public data, W2 list export)
// The list export needs each library title's MyAnimeList id and display title. They live in
// the public `anime` / `manga` tables (policy "Public read access"; `mal_id` is UNIQUE, `id` is the
// primary key), so this is one plain GET per batch of at most `exportIdentityBatchSize` ids, in the
// Browse load class. No adult filter: the export is the owner's own list.
//
// Stateless on purpose: the key set is the account's library, and CatalogStore survives sign-out, so
// nothing is cached here (the account-scoped export owner keeps the per-account identity cache).
// The request is public, but the caller runs it inside its account credential lease; a cancelled
// caller therefore stops this read between batches instead of sending the next one.

@MainActor
extension CatalogStore {
    /// The most ids one identity request carries (keeps the URL short and the plan an index scan).
    nonisolated static let exportIdentityBatchSize = 500

    /// The columns an identity row needs.
    nonisolated static let exportIdentityColumns = "id,mal_id,title_english,title_romaji,title_native"

    /// Public identity rows for `keys`: one `GET /rest/v1/{anime|manga}?select=id,mal_id,title_english,title_romaji,title_native&id=in.(…)`
    /// per at most `exportIdentityBatchSize` ids, anime first, sequential, ids ascending. A title the
    /// catalogue does not return is absent from the result. A failed batch leaves its own keys absent and
    /// the remaining batches still run; this never throws. A transport-level failure (`URLError`: offline,
    /// timeout, host unreachable) is different: it would repeat for every remaining batch, each one walking
    /// through the SDK's retries, so the read stops there and returns what it has. Checks `Task.isCancelled`
    /// before each batch and returns what it has without sending further batches: cancellation is not a
    /// failed batch to skip past (the caller's credential lease cancels this read on an account transition).
    func exportIdentities(for keys: Set<MediaKey>) async -> [MediaKey: ExportCatalogueRow] {
        var found: [MediaKey: ExportCatalogueRow] = [:]
        for kind in [MediaKind.anime, MediaKind.manga] {
            let ids = keys.filter { $0.kind == kind }.map(\.id).sorted()
            var start = 0
            while start < ids.count {
                if Task.isCancelled { return found }
                let end = min(start + Self.exportIdentityBatchSize, ids.count)
                let batch = Array(ids[start..<end])
                start = end
                do {
                    let client = try requiredClient()
                    let rows: LenientRows<ExportIdentityRow> = try await client
                        .from(kind.rawValue)
                        .select(Self.exportIdentityColumns)
                        .in("id", values: batch)
                        .execute()
                        .value
                    for row in rows.rows {
                        let key = MediaKey(kind: kind, id: row.id)
                        guard keys.contains(key) else { continue }
                        found[key] = row.catalogueRow
                    }
                } catch {
                    if Task.isCancelled { return found }
                    #if DEBUG
                    print("[CatalogStore] Export identity batch failed for \(kind.rawValue): \(error)")
                    #endif
                    if error is URLError { return found }
                }
            }
        }
        return found
    }
}

/// One `anime` / `manga` identity row as PostgREST returns it.
private nonisolated struct ExportIdentityRow: Decodable {
    let id: Int
    let malId: Int?
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?

    enum CodingKeys: String, CodingKey {
        case id
        case malId = "mal_id"
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case titleNative = "title_native"
    }

    /// The exporter's value: the first non-empty trimmed title of English, romaji, native.
    var catalogueRow: ExportCatalogueRow {
        let title = [titleEnglish, titleRomaji, titleNative]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return ExportCatalogueRow(title: title, malId: malId)
    }
}

#endif
