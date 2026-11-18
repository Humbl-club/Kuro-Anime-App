//
//  DataSourceCreditTests.swift
//  KuroTests
//
//  Catalogue Task 16: the source credit on title pages. The line names the sources that supplied a title's
//  published values (`data_sources`), links ANN where its terms require a link, never names AniList, and a title
//  no allowed source knows (nil sources, no links) keeps showing its stored title everywhere.
//

import Testing
import Foundation
@testable import Kuro

@MainActor
@Suite("Source credit")
struct DataSourceCreditTests {

    private func link(site: String?, url: String) -> ExternalLink {
        ExternalLink(id: 1, mediaType: "ANIME", mediaId: 7, site: site, url: url, language: nil, color: nil,
                     priority: 1, isDisabled: false, createdAt: Date(timeIntervalSince1970: 0),
                     updatedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func lineOrdersAsGiven() {
        #expect(DataSourceCredit.line(for: ["ann", "wikidata"], german: false) == "Data: Anime News Network, Wikidata")
        #expect(DataSourceCredit.line(for: ["wikidata", "ann"], german: false) == "Data: Wikidata, Anime News Network")
        #expect(DataSourceCredit.line(for: ["mangaupdates"], german: false) == "Data: MangaUpdates")
    }

    @Test func nilWhenEmpty() {
        #expect(DataSourceCredit.line(for: [], german: false) == nil)
        #expect(DataSourceCredit.line(for: [], german: true) == nil)
        #expect(DataSourceCredit.line(for: nil, german: false) == nil)
        // Only unknown codes, or Kuro's own data, name no outside source.
        #expect(DataSourceCredit.line(for: ["editorial", "composer", "kuro"], german: false) == nil)
    }

    @Test func germanLine() {
        #expect(DataSourceCredit.line(for: ["ann", "wikidata"], german: true) == "Daten: Anime News Network, Wikidata")
    }

    @Test func neverNamesAniListAndDedupes() {
        let line = DataSourceCredit.line(for: ["anilist", "wikidata", "AniList", "wikidata", "today"], german: false)
        #expect(line == "Data: Wikidata")
        #expect(DataSourceCredit.line(for: ["anilist"], german: false) == nil)
        #expect(DataSourceCredit.displayNames(for: ["ANILIST", "mal"]).isEmpty)
    }

    @Test func episodesProviderAndPageviewsAreNamed() {
        #expect(DataSourceCredit.line(for: ["episodes_provider"], german: false) == "Data: \(DataSourceCredit.episodesProviderName(german: false))")
        #expect(DataSourceCredit.line(for: ["pageviews"], german: false) == "Data: Wikimedia")
    }

    @Test func annLinkUsesExternalLink() {
        let own = link(site: "Anime News Network", url: "https://www.animenewsnetwork.com/encyclopedia/anime.php?id=4658")
        let other = link(site: "Crunchyroll", url: "https://www.crunchyroll.com/x")
        #expect(DataSourceCredit.link(source: "ann", externalLinks: [other, own]) == URL(string: own.url))
        // A link recognised by host works without the site name.
        let byHost = link(site: nil, url: "https://www.animenewsnetwork.com/encyclopedia/anime.php?id=9")
        #expect(DataSourceCredit.link(source: "ann", externalLinks: [byHost])?.absoluteString == byHost.url)
        // No per-title link: the encyclopedia itself, so the credit still links to ANN.
        #expect(DataSourceCredit.link(source: "ann", externalLinks: [other]) == DataSourceCredit.annEncyclopedia)
        #expect(DataSourceCredit.link(source: "ann", externalLinks: [])?.host == "www.animenewsnetwork.com")
        // Only an https ANN host is accepted from a row.
        let spoof = link(site: "Anime News Network", url: "https://evil.example/animenewsnetwork.com")
        #expect(DataSourceCredit.link(source: "ann", externalLinks: [spoof]) == DataSourceCredit.annEncyclopedia)
        let plain = link(site: "Anime News Network", url: "http://www.animenewsnetwork.com/encyclopedia/anime.php?id=1")
        #expect(DataSourceCredit.link(source: "ann", externalLinks: [plain]) == DataSourceCredit.annEncyclopedia)
    }

    @Test func otherSourcesCarryNoLink() {
        #expect(DataSourceCredit.link(source: "wikidata", externalLinks: []) == nil)
        #expect(DataSourceCredit.link(source: "mangaupdates", externalLinks: []) == nil)
        #expect(DataSourceCredit.link(source: "anilist", externalLinks: []) == nil)
    }

    @Test func attributedLineLinksAnnOnly() throws {
        let own = link(site: "Anime News Network", url: "https://www.animenewsnetwork.com/encyclopedia/anime.php?id=4658")
        let text = try #require(DataSourceCredit.attributed(for: ["ann", "wikidata"], externalLinks: [own], german: false))
        #expect(String(text.characters) == "Data: Anime News Network, Wikidata")
        let links = text.runs.compactMap { run in run.link.map { (String(text[run.range].characters), $0) } }
        #expect(links.count == 1)
        #expect(links.first?.0 == "Anime News Network")
        #expect(links.first?.1 == URL(string: own.url))
        #expect(DataSourceCredit.attributed(for: nil, externalLinks: [own], german: false) == nil)
    }

    @Test func detailSelectsCarryDataSourcesAndCardsDoNot() {
        #expect(CatalogColumns.animeDetail.contains("data_sources"))
        #expect(CatalogColumns.mangaDetail.contains("data_sources"))
        #expect(!CatalogColumns.animeCard.contains("data_sources") && !CatalogColumns.mangaCard.contains("data_sources"))
    }

    private let titleJSON = """
    {"id": 41, "title_english": "Stored Title", "is_adult": false,
     "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z"}
    """

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test func dataSourcesDecodeWhenPresentAndStayNilWhenAbsent() throws {
        let absent = try decoder().decode(Anime.self, from: Data(titleJSON.utf8))
        #expect(absent.dataSources == nil)
        let present = try decoder().decode(Anime.self, from: Data(titleJSON.replacingOccurrences(of: "\"is_adult\"", with: "\"data_sources\": [\"ann\",\"wikidata\"], \"is_adult\"").utf8))
        #expect(present.dataSources == ["ann", "wikidata"])
        let manga = try decoder().decode(Manga.self, from: Data(titleJSON.replacingOccurrences(of: "\"is_adult\"", with: "\"data_sources\": [\"mangaupdates\"], \"is_adult\"").utf8))
        #expect(manga.dataSources == ["mangaupdates"])
    }

    /// Review focus 5: a title no allowed source knows (data_sources nil, no links) that sits in a user's list
    /// keeps its stored title in Collection; the credit simply shows no line.
    @Test func hiddenFromBrowseStaysInCollection() async throws {
        let harness = try FacadeHarness()
        harness.server.respond { request in
            guard request.resource == CollectionContractTests.feed else { return .emptyArray }
            return ListRowJSON.response([CollectionPages.feedRow(0)])
        }
        await harness.signIn()
        let collection = harness.service.collection
        await collection.fetchCollectionFeed()
        let shown = try #require(collection.collectionFeedItems.first)
        #expect(shown.title == "Title 1", "the stored title is shown; nothing in the app filters on source or visibility")
        let anime = try decoder().decode(Anime.self, from: Data(titleJSON.utf8))
        #expect(anime.displayTitle == "Stored Title")
        #expect(DataSourceCredit.line(for: anime.dataSources, german: false) == nil)
        #expect(DataSourceCredit.link(source: "ann", externalLinks: []) != nil, "the link rule never hides the title either")
        await harness.tearDown()
    }
}
