import Foundation
import KuroCore
import KuroLibrary

#if canImport(Supabase)
import Supabase

// MARK: - Reviewed series membership (public data, W6 Collection grouping)
// One GET per medium and batch of at most `seriesMembershipBatch` ids against the public, RLS-select-only
// tables `series_entry_spans` / `series` / `series_sections` (Browse load class; no migration). Only reviewed
// membership counts: series `continuity = verified`, `grouping_state = approved`, section `state = approved`
// (the server filter), and the span's medium equal to the series' medium (checked here, because PostgREST
// cannot compare columns across an embed). A `series` row inserted with its defaults is approved but
// `singleton` and therefore never counts. Automatic franchise components are NOT membership and are never read.
//
// The reader takes no credential lease itself (CatalogStore has no account session); its callers in
// `CollectionStore` run it inside a lease of the captured account because the ids are account data.

@MainActor
extension CatalogStore {
    /// Ids per medium per request.
    nonisolated static let seriesMembershipBatch = 300
    /// A title is not re-read within this window, found or not (negative cache).
    nonisolated static let seriesMembershipTTL: TimeInterval = 86_400

    nonisolated static let seriesMembershipColumns =
        "anime_id,manga_id,medium,"
        + "series!series_entry_spans_series_id_fkey!inner(id,medium,continuity,grouping_state),"
        + "series_sections!series_entry_spans_section_id_fkey!inner(kind,ordinal,name,sort_order,state)"

    var seriesMembershipMap: [MediaKey: SeriesMembership] { seriesMembershipStore }

    func seriesMembership(for key: MediaKey) -> SeriesMembership? { seriesMembershipStore[key] }

    /// Reads reviewed membership for keys not checked within the TTL. Public data; silent on failure
    /// (a failed batch keeps the known membership and records nothing). Never throws.
    /// `checkedAt` is written only for a batch whose request completed while the task was not cancelled, so
    /// a read cancelled by a revoked credential lease leaves no negative cache behind.
    func loadSeriesMembership(for keys: [MediaKey]) async {
        let now = Date()
        let wanted = Set(keys).filter { key in
            guard let checked = seriesMembershipCheckedAt[key] else { return true }
            return now.timeIntervalSince(checked) > Self.seriesMembershipTTL
        }
        guard !wanted.isEmpty else { return }
        for kind in [MediaKind.anime, MediaKind.manga] {
            let ids = wanted.filter { $0.kind == kind }.map(\.id).sorted()
            var start = 0
            while start < ids.count {
                if Task.isCancelled { return }
                let end = min(start + Self.seriesMembershipBatch, ids.count)
                let batch = Array(ids[start..<end])
                start = end
                do {
                    let client = try requiredClient()
                    let rows: LenientRows<SeriesSpanRow> = try await client
                        .from("series_entry_spans")
                        .select(Self.seriesMembershipColumns)
                        .eq("medium", value: kind.rawValue)
                        .in(kind == .anime ? "anime_id" : "manga_id", values: batch)
                        .eq("series.continuity", value: "verified")
                        .eq("series.grouping_state", value: "approved")
                        .eq("series_sections.state", value: "approved")
                        .execute()
                        .value
                    if Task.isCancelled { return }
                    applySeriesMembership(rows.rows, kind: kind, requested: batch, checkedAt: now)
                } catch {
                    if Task.isCancelled { return }
                    #if DEBUG
                    print("[CatalogStore] Series membership batch failed for \(kind.rawValue): \(error)")
                    #endif
                    if error is URLError { return }
                }
            }
        }
    }

    private func applySeriesMembership(_ rows: [SeriesSpanRow], kind: MediaKind, requested: [Int], checkedAt: Date) {
        let asked = Set(requested)
        var found: [MediaKey: SeriesMembership] = [:]
        for row in rows {
            guard let membership = row.membership, membership.medium == kind else { continue }
            guard let id = kind == .anime ? row.animeId : row.mangaId, asked.contains(id) else { continue }
            found[MediaKey(kind: kind, id: id)] = membership
        }
        var changed = false
        for id in requested {
            let key = MediaKey(kind: kind, id: id)
            seriesMembershipCheckedAt[key] = checkedAt
            if let membership = found[key] {
                if seriesMembershipStore[key] != membership {
                    seriesMembershipStore[key] = membership
                    changed = true
                }
            } else if seriesMembershipStore.removeValue(forKey: key) != nil {
                changed = true
            }
        }
        if changed { seriesMembershipVersion += 1 }
    }
}

/// One `series_entry_spans` row with its embedded series and section, as PostgREST returns it.
private nonisolated struct SeriesSpanRow: Decodable {
    struct SeriesPart: Decodable {
        let id: String
        let medium: String
        let continuity: String
        let groupingState: String
        enum CodingKeys: String, CodingKey { case id, medium, continuity, groupingState = "grouping_state" }
    }

    struct SectionPart: Decodable {
        let kind: String
        let ordinal: Int?
        let name: String?
        let sortOrder: Int
        let state: String
        enum CodingKeys: String, CodingKey { case kind, ordinal, name, sortOrder = "sort_order", state }
    }

    let animeId: Int?
    let mangaId: Int?
    let medium: String
    let series: SeriesPart
    let section: SectionPart

    enum CodingKeys: String, CodingKey {
        case animeId = "anime_id", mangaId = "manga_id", medium, series, section = "series_sections"
    }

    /// Defence in depth: the row is re-checked against the reviewed definition even though the
    /// request already filtered it, so a changed or ignored filter can never admit unreviewed membership.
    var membership: SeriesMembership? {
        guard let kind = MediaKind(rawValue: medium),
              let sectionKind = SeriesMembership.SectionKind(rawValue: section.kind),
              SeriesMembership.isReviewed(continuity: series.continuity, groupingState: series.groupingState,
                                          sectionState: section.state, seriesMedium: series.medium, spanMedium: medium)
        else { return nil }
        return SeriesMembership(seriesId: series.id, medium: kind, sectionKind: sectionKind, ordinal: section.ordinal,
                                sortOrder: section.sortOrder, sectionName: section.name ?? "", isReviewed: true)
    }
}

#endif
