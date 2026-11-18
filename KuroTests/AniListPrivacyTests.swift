//
//  AniListPrivacyTests.swift
//  KuroTests
//
//  Catalogue Task 15d: `anilist_id` is private (the Wikidata / ANN crosswalk key), so no app read names it
//  and the detail page's reference links are MyAnimeList only.
//

import Testing
import Foundation
@testable import Kuro

@MainActor
@Suite("AniList id is private: CatalogColumns")
struct CatalogColumnsTests {
    @Test func noSelectNamesAnilistId() {
        for (name, columns) in CatalogColumns.allColumnLists {
            #expect(!columns.contains { $0.contains("anilist") }, "\(name) selects an AniList column")
        }
        for select in [CatalogColumns.characterEmbed, CatalogColumns.staffEmbed, CatalogColumns.authorEmbed,
                       CatalogColumns.studioEmbed, CatalogStore.exportIdentityColumns] {
            #expect(!select.contains("anilist"), "\(select)")
        }
    }
}

@MainActor
@Suite("AniList id is private: reference links")
struct ExternalLinksSectionTests {
    @Test func rendersMyAnimeListOnly() {
        let links = ExternalLinksSection.references(malId: 5114, mediaType: "anime")
        #expect(links.map(\.title) == ["MyAnimeList"])
        #expect(links.first?.url.absoluteString == "https://myanimelist.net/anime/5114")
        #expect(!links.contains { $0.url.host?.contains("anilist") == true })
        #expect(ExternalLinksSection.references(malId: nil, mediaType: "manga").isEmpty)
    }
}
