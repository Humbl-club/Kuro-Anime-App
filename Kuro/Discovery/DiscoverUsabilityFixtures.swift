import Foundation
import KuroCore

#if DEBUG
// MARK: - Discover usability fixtures (UI renders and tests; never shipped)
// Wire rows for the stub PostgREST endpoint of the fixture renders (`StubServer` in KuroTests
// answers `rpc/discover_section_page_v1`, `rpc/discover_mood_v1`, `rpc/media_franchise_ids_v1` and
// `taste_signal_events` with these), plus decoded pages for previews. Covers on s4.anilist.co so
// the artwork seeding of the render suites applies.

enum DiscoverUsabilityFixtures {
    static let animeTitles = ["Frieren", "Mushishi", "Odd Taxi", "Ping Pong", "Mononoke", "Haikyu!!",
                              "Monster", "Paprika", "Natsume's Book of Friends", "Yuru Camp", "Dororo", "Planetes"]
    static let mangaTitles = ["Vagabond", "Yotsuba&!", "Blame!", "Nana", "Dorohedoro", "Pluto",
                              "Monster", "Solanin"]

    /// `count` rows of `discover_section_page_v1` / `discover_mood_v1` for `kind`, ranks from
    /// `firstRank`. `listStatus` marks the row at that index (editorial sections); `reason` names
    /// the seed of a like-last-loved page.
    static func pageRowsJSON(kind: MediaKind, count: Int, firstId: Int? = nil, firstRank: Int = 1,
                             listStatusAt: [Int: String] = [:], reason: (id: Int, title: String)? = nil) -> String {
        let base = firstId ?? (kind == .anime ? 991_000 : 991_500)
        let rows = (0..<max(0, count)).map { i -> String in
            let id = base + i
            let rank = firstRank + i
            let status = listStatusAt[i].map { #""\#($0)""# } ?? "null"
            let reasonId = reason.map { String($0.id) } ?? "null"
            let reasonTitle = reason.map { #""\#($0.title)""# } ?? "null"
            switch kind {
            case .anime:
                let title = animeTitles[i % animeTitles.count]
                return #"{"media_type":"ANIME","rank":\#(rank),"id":\#(id),"title_english":"\#(title)","title_romaji":"\#(title)","title_native":null,"cover_image_large":"https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/du\#(i).jpg","cover_image_medium":null,"banner_image":null,"format":"\#(i % 4 == 3 ? "MOVIE" : "TV")","status":"\#(i % 5 == 4 ? "RELEASING" : "FINISHED")","episode_count":\#(i % 4 == 3 ? 1 : 12 + (i % 3) * 12),"chapter_count":null,"volumes":null,"season_year":\#(2008 + i),"start_date_year":\#(2008 + i),"average_score":\#(80 + i % 10),"popularity":\#(90_000 - i * 1_000),"trending":\#(50 - i),"favourites":\#(5_000 - i * 100),"genres":["Drama"],"created_at":"2026-01-01T00:00:00+00:00","franchise_id":\#(id),"list_status":\#(status),"reason_media_id":\#(reasonId),"reason_title":\#(reasonTitle)}"#
            case .manga:
                let title = mangaTitles[i % mangaTitles.count]
                return #"{"media_type":"MANGA","rank":\#(rank),"id":\#(id),"title_english":"\#(title)","title_romaji":"\#(title)","title_native":null,"cover_image_large":"https://s4.anilist.co/file/anilistcdn/media/manga/cover/large/du\#(i).jpg","cover_image_medium":null,"banner_image":null,"format":"MANGA","status":"FINISHED","episode_count":null,"chapter_count":\#(40 + i * 10),"volumes":\#(5 + i),"season_year":null,"start_date_year":\#(1998 + i),"average_score":\#(80 + i % 10),"popularity":\#(60_000 - i * 1_000),"trending":\#(30 - i),"favourites":\#(3_000 - i * 100),"genres":["Seinen"],"created_at":"2026-01-01T00:00:00+00:00","franchise_id":\#(id),"list_status":\#(status),"reason_media_id":\#(reasonId),"reason_title":\#(reasonTitle)}"#
            }
        }
        return "[" + rows.joined(separator: ",") + "]"
    }

    /// `media_franchise_ids_v1` rows: every key labelled `label(key)` (default: itself).
    static func franchiseRowsJSON(_ keys: [MediaKey], label: (MediaKey) -> Int = { $0.id }) -> String {
        let rows = keys.map { key in
            #"{"media_type":"\#(key.kind == .manga ? "MANGA" : "ANIME")","media_id":\#(key.id),"franchise_id":\#(label(key))}"#
        }
        return "[" + rows.joined(separator: ",") + "]"
    }

    /// `taste_signal_events` rows of the caller (newest first), `event_type` like 'deck_skip'.
    static func deckSignalRowsJSON(_ signals: [(key: MediaKey, eventType: String, at: Date)]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = signals.map { signal in
            #"{"media_type":"\#(signal.key.kind == .manga ? "MANGA" : "ANIME")","media_id":\#(signal.key.id),"event_type":"\#(signal.eventType)","created_at":"\#(formatter.string(from: signal.at))"}"#
        }
        return "[" + rows.joined(separator: ",") + "]"
    }

    /// A decoded page (previews): `count` cards of `kind`.
    static func page(kind: MediaKind, count: Int, reason: (id: Int, title: String)? = nil,
                     origin: DiscoverPage.Origin = .server) -> DiscoverPage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = (try? decoder.decode([DiscoverPageRow].self,
                                        from: Data(pageRowsJSON(kind: kind, count: count, reason: reason).utf8))) ?? []
        return DiscoverPage(items: rows.compactMap(\.item), next: nil,
                            reason: rows.lazy.compactMap(\.reason).first, origin: origin)
    }
}
#endif
