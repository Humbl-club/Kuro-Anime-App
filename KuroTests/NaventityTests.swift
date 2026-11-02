//
//  NaventityTests.swift
//  KuroTests
//
//  Navigation lane "entity" (docs/superpowers/specs/2026-11-02-navigation-contract-design.md): the
//  character, staff, studio and author pages are journey pages. Covered here without UI:
//    - the chains a person page takes part in push inside one journey and dedupe (N5) through the
//      foundation's `JourneyNavigator` / `JourneyPolicy`;
//    - the staff page lists anime AND manga works (`manga_staff` reader: request shape, adult filtering,
//      merge rule) — the §6 gap "the staff sheet lists anime only";
//    - the medium filter rule and the character directory's journey identity.
//

import Testing
import Foundation
import SwiftUI
import KuroCore
@testable import Kuro

// MARK: - Journey chains

@MainActor
@Suite("Nav entity: person and studio pages push inside the journey")
struct NaventityJourneyTests {

    private func character(_ id: Int) throws -> Character {
        try JSONDecoder().decode(Character.self, from: Data(#"{"id":\#(id),"name_full":"Character \#(id)"}"#.utf8))
    }

    private func staff(_ id: Int) throws -> Staff {
        try JSONDecoder().decode(Staff.self, from: Data(#"{"id":\#(id),"name_full":"Staff \#(id)"}"#.utf8))
    }

    private func studio(_ id: Int) throws -> Studio {
        try JSONDecoder().decode(Studio.self, from: Data(#"{"id":\#(id),"name":"Studio \#(id)"}"#.utf8))
    }

    private func author(_ id: Int) throws -> Author {
        try JSONDecoder().decode(Author.self, from: Data(#"{"id":\#(id),"name_full":"Author \#(id)"}"#.utf8))
    }

    @Test("Each entity route is a journey page (pushed), never a tool, and builds its own page")
    func entityRoutesArePages() throws {
        let pages: [JourneyPage] = [
            .character(try character(1)), .staff(try staff(2)), .studio(try studio(3)), .author(try author(4)),
        ]
        for page in pages {
            #expect(RoutePolicy.journeyPage(for: .page(page)) == page)
            switch (page, JourneyPolicy.destination(for: page)) {
            case (.character(let c), .character(let built)): #expect(built.id == c.id)
            case (.staff(let s), .staff(let built)): #expect(built.id == s.id)
            case (.studio(let s), .studio(let built)): #expect(built.id == s.id)
            case (.author(let a), .author(let built)): #expect(built.id == a.id)
            default: Issue.record("\(page.id) built the wrong destination")
            }
        }
        // The chrome's compact-bar title is the entity's name.
        #expect(JourneyPage.character(try character(1)).title == "Character 1")
        #expect(JourneyPage.studio(try studio(3)).title == "Studio 3")
    }

    @Test("Detail → character → appearance → staff → work: every tap pushes one level, Back pops one")
    func characterChainPushes() throws {
        let navigator = JourneyNavigator(root: .media(MediaRoute(kind: .anime, id: 10)))
        navigator.routes.openCharacter(try character(1))
        navigator.routes.openMedia(MediaRoute(kind: .manga, id: 20))
        navigator.routes.openStaff(try staff(2))
        navigator.routes.openMedia(MediaRoute(kind: .anime, id: 30))
        #expect(navigator.path.map(\.id) == ["character:1", "media:manga:20", "staff:2", "media:anime:30"])
        navigator.pop()
        #expect(navigator.top.id == "staff:2")
        navigator.pop()
        #expect(navigator.top.id == "media:manga:20")
    }

    @Test("N5: an appearance that is the journey's root pops back to it (no copy of the detail)")
    func appearanceBackToRoot() throws {
        let navigator = JourneyNavigator(root: .media(MediaRoute(kind: .anime, id: 10)))
        navigator.routes.openCharacter(try character(1))
        navigator.routes.openMedia(MediaRoute(kind: .anime, id: 10))
        #expect(navigator.path.isEmpty)
        #expect(navigator.top.id == "media:anime:10")
    }

    @Test("N5: author → work → the same author pops back to the author; double tap on a person does nothing")
    func authorPingPong() throws {
        let navigator = JourneyNavigator(root: .media(MediaRoute(kind: .manga, id: 5)))
        let writer = try author(4)
        navigator.routes.openAuthor(writer)
        navigator.routes.openMedia(MediaRoute(kind: .manga, id: 6))
        #expect(JourneyPolicy.step(opening: .author(writer), root: navigator.root, path: navigator.path) == .popTo(keep: 1))
        navigator.routes.openAuthor(writer)
        #expect(navigator.path.map(\.id) == ["author:4"])
        navigator.routes.openAuthor(writer)
        #expect(navigator.path.map(\.id) == ["author:4"])
    }

    @Test("Anime 7 and manga 7 from one staff page are different pages; staff 5 and author 5 too")
    func kindsStayDistinct() throws {
        let navigator = JourneyNavigator(root: .staff(try staff(5)))
        navigator.routes.openMedia(MediaRoute(kind: .anime, id: 7))
        navigator.routes.openMedia(MediaRoute(kind: .manga, id: 7))
        navigator.routes.openAuthor(try author(5))
        #expect(navigator.path.map(\.id) == ["media:anime:7", "media:manga:7", "author:5"])
    }

    @Test("A tool opened from a work never changes the path; a person tapped while it is open closes it and pushes")
    func toolsReturnToTheirPage() throws {
        let navigator = JourneyNavigator(root: .studio(try studio(3)))
        navigator.routes.openMedia(MediaRoute(kind: .anime, id: 7))
        navigator.routes.presentAddToClub(MediaKey(kind: .anime, id: 7))
        #expect(navigator.tool?.id == "addToClub:anime:7")
        #expect(navigator.path.map(\.id) == ["media:anime:7"])
        navigator.routes.openStaff(try staff(2))
        #expect(navigator.tool == nil)
        #expect(navigator.path.map(\.id) == ["media:anime:7", "staff:2"])
    }

    @Test("The character directory has a stable per-cast id; a second See all pops back to it")
    func castDirectoryIdentity() throws {
        #expect(CastDirectory.journeyID(characterIDs: [3, 1, 2]) == "characters:3-1-2")
        #expect(CastDirectory.journeyID(characterIDs: [1, 2, 3]) != CastDirectory.journeyID(characterIDs: [3, 1, 2]))
        #expect(CastDirectory.journeyID(characterIDs: []) == "characters:")

        let id = CastDirectory.journeyID(characterIDs: [1, 2])
        let directory = JourneyPage.seeAll(AnyJourneyPage(id: id, title: "Characters") { EmptyView() })
        let navigator = JourneyNavigator(root: .media(MediaRoute(kind: .anime, id: 10)))
        navigator.routes.openPage(directory)
        navigator.routes.openPage(.character(try character(1)))
        navigator.routes.openPage(.seeAll(AnyJourneyPage(id: id, title: "Characters") { EmptyView() }))
        #expect(navigator.path.map(\.id) == ["seeAll:characters:1-2"])
    }
}

// MARK: - Entity works rules

@MainActor
@Suite("Nav entity: works rules")
struct NaventityWorksRuleTests {

    private func media(_ kind: MediaKind, _ id: Int) -> Media {
        Media(
            id: id, kind: kind, title: "Title \(id)", imageURL: nil, year: "2020",
            displayDescription: "", episodes: nil, chapters: nil,
            rating: nil, genres: nil, statusRaw: nil, formatRaw: nil,
            popularityValue: nil, trendingValue: nil, createdAtValue: nil
        )
    }

    @Test("Staff works: anime first then manga; a duplicate credit is listed once; other roles stay")
    func staffWorksMerge() {
        let anime = [(media: media(.anime, 1), role: "Original Creator"), (media: media(.anime, 1), role: "Original Creator")]
        let manga = [(media: media(.manga, 1), role: "Story & Art"), (media: media(.manga, 1), role: "Art")]
        let merged = EntityWorks.staffWorks(anime: anime, manga: manga)
        #expect(merged.map { "\($0.media.kind.rawValue):\($0.media.id):\($0.role)" } == [
            "anime:1:Original Creator", "manga:1:Story & Art", "manga:1:Art",
        ])
        #expect(EntityWorks.staffWorks(anime: [], manga: []).isEmpty)
    }

    @Test("Medium filters only when the works span anime and manga")
    func mediumFilters() {
        #expect(EntityWorks.mediumFilters(for: []).isEmpty)
        #expect(EntityWorks.mediumFilters(for: [.anime, .anime]).isEmpty)
        #expect(EntityWorks.mediumFilters(for: [.manga]).isEmpty)
        #expect(EntityWorks.mediumFilters(for: [.manga, .anime]) == [.all, .anime, .manga])
    }

    @Test("Medium filter matching")
    func mediumMatching() {
        #expect(EntityWorks.matches(.anime, filter: .all))
        #expect(EntityWorks.matches(.manga, filter: .all))
        #expect(EntityWorks.matches(.anime, filter: .anime))
        #expect(!EntityWorks.matches(.manga, filter: .anime))
        #expect(EntityWorks.matches(.manga, filter: .manga))
        #expect(!EntityWorks.matches(.anime, filter: .manga))
    }

    @Test("Manga staff roles fall into the staff page's craft filters")
    func mangaRolesFilter() {
        #expect(StaffRoleFilter.from(role: "Story & Art") == .writer)
        #expect(StaffRoleFilter.from(role: "Story") == .writer)
        #expect(StaffRoleFilter.from(role: "Original Creator") == .writer)
    }
}

// MARK: - CatalogStore staff manga reader

@MainActor
@Suite("Nav entity: staff manga reader", .timeLimit(.minutes(1)))
struct NaventityStaffReaderTests {

    private static let animeRows = #"""
    [{"role":"Original Creator","anime":{"id":11,"title_english":"Show","title_romaji":null,"cover_image_large":null,"average_score":80,"season_year":2019,"format":"TV","status":"FINISHED","genres":["Drama"],"is_adult":false,"episodes":12}}]
    """#

    private static let mangaRows = #"""
    [
      {"role":"Story & Art","manga":{"id":21,"title_english":"Book","title_romaji":null,"cover_image_large":null,"average_score":85,"start_date_year":2015,"format":"MANGA","status":"FINISHED","genres":["Drama"],"is_adult":false,"chapters":90}},
      {"role":"Story","manga":{"id":22,"title_english":"Adult","title_romaji":null,"cover_image_large":null,"average_score":70,"start_date_year":2016,"format":"MANGA","status":"FINISHED","genres":[],"is_adult":true,"chapters":10}},
      {"role":"Art","manga":{"id":23,"title_english":"Filtered","title_romaji":null,"cover_image_large":null,"average_score":60,"start_date_year":2017,"format":"MANGA","status":"FINISHED","genres":["Hentai"],"is_adult":false,"chapters":5}}
    ]
    """#

    @Test("manga_staff read: the staff id, the inner manga embed, non-adult, ordered by score, bounded")
    func requestShape() async throws {
        let harness = try PublicDataHarness()
        _ = await harness.service.catalog.fetchMangaByStaff(staffId: 990_601)
        let request = try #require(harness.requests(to: "manga_staff").first)
        #expect(request.method == "GET")
        #expect(request.query("staff_id") == "eq.990601")
        #expect(request.query("manga.is_adult") == "eq.false")
        #expect(request.query("select")?.contains("manga!inner(") == true)
        #expect(request.query("select")?.contains("role") == true)
        #expect(request.query("order") == "manga(average_score).desc.nullslast,id.asc.nullslast")
        #expect(request.query("limit") == "\(CatalogColumns.entityWorksRowLimit)")
        await harness.tearDown()
    }

    @Test("Staff works: anime and manga both read; adult and Hentai rows are dropped; roles kept")
    func staffWorksCombined() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "anime_staff": return .json(Self.animeRows)
            case "manga_staff": return .json(Self.mangaRows)
            default: return .emptyArray
            }
        }
        let works = await harness.service.catalog.fetchStaffWorks(staffId: 990_602)
        #expect(works.map { "\($0.media.kind.rawValue):\($0.media.id):\($0.role)" } == [
            "anime:11:Original Creator", "manga:21:Story & Art",
        ])
        #expect(harness.requests(to: "anime_staff").count == 1)
        #expect(harness.requests(to: "manga_staff").count == 1)

        // Cached for the page's lifetime in the stack: Back + reopen asks nothing again.
        _ = await harness.service.catalog.fetchStaffWorks(staffId: 990_602)
        #expect(harness.requests(to: "manga_staff").count == 1)
        await harness.tearDown()
    }

    @Test("Memory pressure sheds the staff manga cache: the next read asks again")
    func memoryPressureClears() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "manga_staff" ? .json(Self.mangaRows) : .emptyArray
        }
        let catalog = harness.service.catalog
        _ = await catalog.fetchMangaByStaff(staffId: 990_603)
        catalog.trimCachesForMemoryPressure()
        _ = await catalog.fetchMangaByStaff(staffId: 990_603)
        #expect(harness.requests(to: "manga_staff").count == 2)
        await harness.tearDown()
    }
}
