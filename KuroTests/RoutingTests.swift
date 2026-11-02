//
//  RoutingTests.swift
//  KuroTests
//
//  The typed navigation outputs (Kuro/Views/Routing/KuroRoutes.swift): a feature view emits a route
//  and the nearest presenter builds the sibling feature's detail or sheet. These pin the pure rules
//  the presenter runs: route identity (kind-prefixed, so anime 7 and manga 7 never collapse), the
//  slot update (a double tap never stacks or re-presents the same sheet; a different route replaces
//  the shown one) and the route -> constructed-destination mapping (exactly what the call sites
//  built before the migration).
//

import Testing
import Foundation
import KuroCore
@testable import Kuro

@MainActor
@Suite("Routing: typed navigation outputs")
struct RoutingTests {

    // MARK: Fixtures

    private func anime(_ id: Int) throws -> Anime {
        let json = #"{"id":\#(id),"is_adult":false,"genres":[],"created_at":0,"updated_at":0}"#
        return try JSONDecoder().decode(Anime.self, from: Data(json.utf8))
    }

    private func manga(_ id: Int) throws -> Manga {
        let json = #"{"id":\#(id),"is_adult":false,"genres":[],"created_at":0,"updated_at":0}"#
        return try JSONDecoder().decode(Manga.self, from: Data(json.utf8))
    }

    private func media(_ kind: MediaKind, _ id: Int) -> Media {
        Media(
            id: id, kind: kind, title: "Title \(id)", imageURL: nil, year: "2020",
            displayDescription: "", episodes: kind == .anime ? 12 : nil, chapters: kind == .manga ? 40 : nil,
            rating: nil, genres: nil, statusRaw: nil, formatRaw: nil,
            popularityValue: nil, trendingValue: nil, createdAtValue: nil
        )
    }

    // MARK: Identity

    @Test("Route ids are kind-prefixed: kind, id and route type all distinguish routes")
    func identityTable() throws {
        let rows: [(route: AppRoute, id: String)] = [
            (.media(MediaRoute(kind: .anime, id: 7)), "media:anime:7"),
            (.media(MediaRoute(kind: .manga, id: 7)), "media:manga:7"),
            (.media(MediaRoute(MediaKey(kind: .anime, id: 42))), "media:anime:42"),
            (.media(MediaRoute(anime: try anime(7))), "media:anime:7"),
            (.media(MediaRoute(manga: try manga(7))), "media:manga:7"),
            (.club(id: "c-1"), "club:c-1"),
            (.trackingEditor(TrackingEditorRequest(media: media(.anime, 7))), "tracking:anime:7"),
            (.trackingEditor(TrackingEditorRequest(media: media(.manga, 7))), "tracking:manga:7"),
            (.addToClub(MediaKey(kind: .anime, id: 7)), "addToClub:anime:7"),
            (.addToClub(MediaKey(kind: .manga, id: 7)), "addToClub:manga:7"),
        ]
        for row in rows {
            #expect(row.route.id == row.id)
        }
        // Every row except the two preloaded twins of a key-only route is a distinct route.
        #expect(Set(rows.map(\.route.id)).count == rows.count - 2)
    }

    // MARK: Slot update (double tap, replace)

    @Test("Slot update: present, ignore the same route, replace a different one")
    func updateTable() throws {
        let anime7 = AppRoute.media(MediaRoute(kind: .anime, id: 7))
        let manga7 = AppRoute.media(MediaRoute(kind: .manga, id: 7))
        let anime8 = AppRoute.media(MediaRoute(kind: .anime, id: 8))
        let anime7Preloaded = AppRoute.media(MediaRoute(anime: try anime(7)))
        let editAnime7 = AppRoute.trackingEditor(TrackingEditorRequest(media: media(.anime, 7)))
        let clubA = AppRoute.club(id: "a")
        let clubB = AppRoute.club(id: "b")

        // (current, requested, expected id stored; nil = nothing changes)
        let rows: [(name: String, current: AppRoute?, requested: AppRoute, stored: String?)] = [
            ("nothing shown presents", nil, anime7, "media:anime:7"),
            ("double tap on the same card", anime7, anime7, nil),
            ("same title, already preloaded", anime7Preloaded, anime7, nil),
            ("same title, preloaded second", anime7, anime7Preloaded, nil),
            ("anime 7 then manga 7", anime7, manga7, "media:manga:7"),
            ("a second detail link replaces", anime7, anime8, "media:anime:8"),
            ("detail then the title's editor", anime7, editAnime7, "tracking:anime:7"),
            ("editor then the title's detail", editAnime7, anime7, "media:anime:7"),
            ("same club twice", clubA, clubA, nil),
            ("another club replaces", clubA, clubB, "club:b"),
            ("club over a detail replaces", anime7, clubA, "club:a"),
        ]
        for row in rows {
            let stored = RoutePolicy.update(current: row.current, requested: row.requested)
            #expect(stored?.id == row.stored, "\(row.name)")
        }
    }

    @Test("A double tap stores one route: replaying the taps leaves the first presentation untouched")
    func doubleTapNeverStacks() {
        let tap = AppRoute.media(MediaRoute(kind: .anime, id: 7))
        var slot: AppRoute? = nil
        var writes = 0
        for _ in 0..<2 {
            if let next = RoutePolicy.update(current: slot, requested: tap) {
                slot = next
                writes += 1
            }
        }
        #expect(writes == 1)
        #expect(slot?.id == "media:anime:7")
    }

    // MARK: Destination (what the presenter constructs)

    @Test("Destination: what each route constructs, exactly as the call sites did")
    func destinationTable() throws {
        // Key-only detail: the loader sheet, keyed by kind and id.
        for key in [MediaKey(kind: .anime, id: 7), MediaKey(kind: .manga, id: 7)] {
            guard case .mediaLoader(let loaded) = RoutePolicy.destination(for: .media(MediaRoute(key))) else {
                Issue.record("key-only \(key) did not map to the loader"); continue
            }
            #expect(loaded == key)
        }

        // Preloaded detail (Concierge): the detail view itself, with the caller's model.
        guard case .animeDetail(let shownAnime) = RoutePolicy.destination(for: .media(MediaRoute(anime: try anime(11)))) else {
            Issue.record("preloaded anime did not map to AnimeDetailView"); return
        }
        #expect(shownAnime.id == 11)
        guard case .mangaDetail(let shownManga) = RoutePolicy.destination(for: .media(MediaRoute(manga: try manga(12)))) else {
            Issue.record("preloaded manga did not map to MangaDetailView"); return
        }
        #expect(shownManga.id == 12)

        // Club: the club id as given.
        guard case .club(let clubId) = RoutePolicy.destination(for: .club(id: "club-uuid")) else {
            Issue.record("club route did not map to the club detail"); return
        }
        #expect(clubId == "club-uuid")

        // Tracking editor: the caller's media (title, poster, totals) and its key.
        guard case .trackingEditor(let edited) = RoutePolicy.destination(for: .trackingEditor(TrackingEditorRequest(media: media(.manga, 9)))) else {
            Issue.record("tracking route did not map to the editor"); return
        }
        #expect(edited.kind == .manga && edited.id == 9 && edited.title == "Title 9" && edited.chapters == 40)

        // Add to club: AddToClubRailSheet takes the upper-case type string.
        let addRows: [(key: MediaKey, mediaId: Int, mediaType: String)] = [
            (MediaKey(kind: .anime, id: 7), 7, "ANIME"),
            (MediaKey(kind: .manga, id: 7), 7, "MANGA"),
        ]
        for row in addRows {
            guard case .addToClub(let mediaId, let mediaType) = RoutePolicy.destination(for: .addToClub(row.key)) else {
                Issue.record("add-to-club \(row.key) did not map to the club rail sheet"); continue
            }
            #expect(mediaId == row.mediaId)
            #expect(mediaType == row.mediaType)
        }
    }
}
