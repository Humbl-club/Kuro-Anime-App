import Foundation
import KuroCore
import KuroLibrary
import SwiftUI
import Testing
@testable import Kuro

//  DUpageTests.swift
//  KuroTests
//
//  Discover usability, lane A (the page; spec docs/superpowers/specs/2026-11-04-discover-usability-design.md):
//  the page build (R2, D5, D7, D16), the cap and More lists (R7), purposes (R1), contents and the
//  pinned index (§5.10), visit memory and NEW marks (§5.8, D18), the progress hook (§5.9), the end
//  tally (§5.7), the D10 refine words, the kind kicker (§5.11), the mood keys (§5.4) and the page's
//  feedback (R4, R5, D12). Pure where possible; the feedback tests run over a signed-in test graph
//  (no network: an in-process stub PostgREST endpoint).

// MARK: - Fixture

/// The usability fixture: distinct franchises per section, plus the live build's repeats (Attack on
/// Titan in New to you AND Essential anime; two Demon Slayer entries side by side in Trending).
nonisolated enum DUFixture {
    static func art(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    static let covers = ["anime0.jpg", "anime1.jpg", "anime2.jpg", "anime3.jpg", "journal-anime-12-cover.jpg",
                         "journal-anime-16-cover.jpg", "journal-anime-22-cover.jpg"]
    static let banners = ["anime0-banner.jpg", "anime1-banner.jpg", "anime3-banner.jpg", "journal-anime-22-banner.jpg",
                          "journal-anime-15-banner.jpg"]
    static let mangaCovers = ["manga0.jpg", "manga1.jpg", "manga2.jpg", "manga3.jpg", "journal-manga-13-cover.jpg",
                              "journal-manga-16-cover.jpg", "journal-manga-23-cover.jpg"]

    /// (id, title, episodes, status, year, score)
    static let anime: [Int: (String, Int?, String, Int, Int)] = [
        1: ("Attack on Titan", 25, "FINISHED", 2013, 85), 2: ("Frieren: Beyond Journey's End", 28, "FINISHED", 2023, 91),
        3: ("Mushishi", 26, "FINISHED", 2005, 87), 4: ("Demon Slayer: Kimetsu no Yaiba", 26, "FINISHED", 2019, 84),
        5: ("Demon Slayer: Swordsmith Village Arc", 11, "FINISHED", 2023, 82), 6: ("Mob Psycho 100", 12, "FINISHED", 2016, 86),
        7: ("Cowboy Bebop", 26, "FINISHED", 1998, 88), 8: ("Dandadan", 12, "RELEASING", 2024, 83),
        9: ("Steins;Gate", 24, "FINISHED", 2011, 90), 10: ("Fullmetal Alchemist: Brotherhood", 64, "FINISHED", 2009, 92),
        11: ("Hunter x Hunter", 148, "FINISHED", 2011, 90), 12: ("Vinland Saga", 24, "FINISHED", 2019, 88),
        13: ("Made in Abyss", 13, "FINISHED", 2017, 85), 14: ("Violet Evergarden", 13, "FINISHED", 2018, 86),
        15: ("Odd Taxi", 13, "FINISHED", 2021, 85), 16: ("Ping Pong the Animation", 11, "FINISHED", 2014, 87),
        17: ("Kaguya-sama: Love Is War", 12, "FINISHED", 2019, 84), 18: ("Spy x Family", 12, "RELEASING", 2025, 83),
        19: ("Bocchi the Rock!", 12, "RELEASING", 2025, 88), 20: ("Sonny Boy", 12, "FINISHED", 2021, 80),
        21: ("Ghost in the Shell", 1, "FINISHED", 1995, 83), 22: ("Neon Genesis Evangelion", 26, "FINISHED", 1995, 83),
        23: ("Serial Experiments Lain", 13, "FINISHED", 1998, 80), 24: ("Monogatari", 15, "FINISHED", 2009, 84),
        25: ("Natsume's Book of Friends", 13, "FINISHED", 2008, 85), 26: ("March Comes in Like a Lion", 22, "FINISHED", 2016, 87),
        27: ("Haikyu!!", 25, "FINISHED", 2014, 85), 28: ("Space Brothers", 99, "FINISHED", 2012, 86),
        29: ("Great Pretender", 23, "FINISHED", 2020, 82), 30: ("Samurai Champloo", 26, "FINISHED", 2004, 85),
        31: ("Trigun", 26, "FINISHED", 1998, 80), 32: ("Planetes", 26, "FINISHED", 2003, 83),
        33: ("Akira", 1, "FINISHED", 1988, 82), 34: ("Perfect Blue", 1, "FINISHED", 1998, 85),
        35: ("Your Name", 1, "FINISHED", 2016, 86), 36: ("Mononoke", 12, "FINISHED", 2007, 82),
        37: ("Kino's Journey", 13, "FINISHED", 2003, 80), 38: ("Barakamon", 12, "FINISHED", 2014, 82),
        39: ("Yuru Camp", 12, "FINISHED", 2018, 82), 40: ("Run with the Wind", 23, "FINISHED", 2018, 86),
        41: ("Blue Lock", 24, "RELEASING", 2025, 80), 42: ("Chainsaw Man", 12, "FINISHED", 2022, 84),
        43: ("Jujutsu Kaisen", 24, "FINISHED", 2020, 86), 44: ("Pluto", 8, "FINISHED", 2023, 85),
        45: ("Delicious in Dungeon", 24, "RELEASING", 2025, 86), 46: ("The Apothecary Diaries", 24, "RELEASING", 2025, 88),
        47: ("Oshi no Ko", 11, "RELEASING", 2025, 84), 48: ("Kaiju No. 8", 12, "RELEASING", 2025, 79)
    ]

    static let manga: [Int: (String, Int?, String, Int, Int)] = [
        501: ("Berserk", nil, "RELEASING", 1989, 93), 502: ("Vagabond", 327, "HIATUS", 1998, 92),
        503: ("Monster", 162, "FINISHED", 1994, 91), 504: ("Goodnight Punpun", 147, "FINISHED", 2007, 90),
        505: ("20th Century Boys", 249, "FINISHED", 1999, 89), 506: ("Yotsuba&!", nil, "RELEASING", 2003, 88),
        507: ("Slam Dunk", 276, "FINISHED", 1990, 90), 508: ("Nana", 84, "HIATUS", 2000, 87),
        509: ("Chainsaw Man", 120, "RELEASING", 2018, 86), 510: ("Solo Leveling", 200, "FINISHED", 2018, 84),
        511: ("Blue Period", nil, "RELEASING", 2017, 85), 512: ("Dorohedoro", 167, "FINISHED", 2000, 86),
        513: ("Witch Hat Atelier", nil, "RELEASING", 2016, 90), 514: ("The Summer Hikaru Died", nil, "RELEASING", 2021, 85),
        515: ("Look Back", 1, "FINISHED", 2021, 88), 516: ("Kingdom", nil, "RELEASING", 2006, 89),
        517: ("Golden Kamuy", 314, "FINISHED", 2014, 88), 518: ("Oyasumi Punpun", 147, "FINISHED", 2007, 84),
        519: ("Sakamoto Days", nil, "RELEASING", 2020, 82), 520: ("Kagurabachi", nil, "RELEASING", 2023, 81),
        521: ("Delicious in Dungeon", 97, "FINISHED", 2014, 88), 522: ("A Silent Voice", 62, "FINISHED", 2013, 86),
        523: ("Pluto", 65, "FINISHED", 2003, 88), 524: ("Planetes", 26, "FINISHED", 1999, 86),
        525: ("Ashita no Joe", 171, "FINISHED", 1968, 85), 526: ("Lone Wolf and Cub", 142, "FINISHED", 1970, 85)
    ]

    static let sections: [String: [Int]] = [
        "essentials": [1, 10, 9, 11, 7, 22, 24, 12, 13, 14, 2],
        "new_to_you": [1, 15, 16, 20, 23, 25, 26, 28, 32, 37, 38, 36],
        "current_season": [3, 8, 45, 46, 47, 48, 41, 18, 19],
        "trending": [4, 5, 43, 42, 17, 27, 6, 29, 44, 40, 39, 31],
        "classics": [33, 34, 21, 30, 35, 7, 31],
        "top_rated": [10, 2, 9, 11, 7],
        "newly_added": [48, 47, 46, 45],
        "airing_today": [8, 47, 48, 19]
    ]

    static let mangaSections: [String: [Int]] = [
        "essentials": [501, 502, 503, 504, 505, 506, 507, 508],
        "new_to_you": [509, 510, 511, 512, 513, 514, 515, 516, 517, 519, 520, 521, 522, 523, 524, 525, 526],
        "trending": [509, 510, 519, 520, 511],
        "classics": [525, 526, 507, 505, 503],
        "top_rated": [501, 502, 503],
        "newly_added": [520, 519]
    ]

    static func animeRow(_ id: Int) -> String {
        guard let seed = anime[id] else { return "" }
        let cover = covers[id % covers.count]
        let banner = id % 3 == 0 ? "null" : "\"\(art(banners[id % banners.count]))\""
        let episodes = seed.1.map(String.init) ?? "null"
        let format = seed.1 == 1 ? "MOVIE" : "TV"
        return """
        {"id":\(id),"title_english":"\(seed.0)","title_romaji":null,"title_native":null,
         "cover_image_large":"\(art(cover))","cover_image_medium":"\(art(cover))","banner_image":\(banner),
         "format":"\(format)","status":"\(seed.2)","episode_count":\(episodes),"season_year":\(seed.3),"start_date_year":\(seed.3),
         "average_score":\(seed.4),"popularity":\(100_000 - id * 100),"trending":\(60 - id),"favourites":9000,"genres":["Drama"],"rank":null}
        """
    }

    static func mangaRow(_ id: Int) -> String {
        guard let seed = manga[id] else { return "" }
        let cover = mangaCovers[id % mangaCovers.count]
        let chapters = seed.1.map(String.init) ?? "null"
        return """
        {"id":\(id),"title_english":"\(seed.0)","title_romaji":null,"title_native":null,
         "cover_image_large":"\(art(cover))","cover_image_medium":"\(art(cover))",
         "format":"MANGA","status":"\(seed.2)","chapter_count":\(chapters),"start_date_year":\(seed.3),
         "average_score":\(seed.4),"popularity":\(90_000 - id),"trending":30,"favourites":7000,"genres":["Seinen"],"rank":null}
        """
    }

    static func rail(_ name: String) -> String { "[" + (sections[name] ?? []).map(animeRow).joined(separator: ",") + "]" }
    static func mangaRail(_ name: String) -> String { "[" + (mangaSections[name] ?? []).map(mangaRow).joined(separator: ",") + "]" }

    static func bundleJSON() -> String {
        """
        {"anime":{"essentials":\(rail("essentials")),"classics":\(rail("classics")),"new_to_you":\(rail("new_to_you")),
                  "trending":\(rail("trending")),"top_rated":\(rail("top_rated")),"newly_added":\(rail("newly_added")),
                  "airing_today":\(rail("airing_today")),"current_season":\(rail("current_season"))},
         "manga":{"essentials":\(mangaRail("essentials")),"classics":\(mangaRail("classics")),"new_to_you":\(mangaRail("new_to_you")),
                  "trending":\(mangaRail("trending")),"top_rated":\(mangaRail("top_rated")),"newly_added":\(mangaRail("newly_added"))}}
        """
    }

    /// Today's pick: Mushishi (also in This season, so the season section loses it to the lead).
    static func dailyFeatureJSON() -> String {
        """
        [{"media_type":"ANIME","media_id":3,"title":"Mushishi","cover_image_large":"\(art("journal-anime-12-cover.jpg"))",
          "banner_image":"\(art("journal-anime-22-banner.jpg"))","genres":["Mystery","Slice of Life"],"score":87,"year":2005,
          "format":"TV","argument":"Quiet, strange and kind: ten-minute stories that stay with you for days."}]
        """
    }

    static func responder() -> StubServer.Responder {
        let bundle = bundleJSON()
        let feature = dailyFeatureJSON()
        return { request in
            switch request.resource ?? "" {
            case "rpc/discover_bundle": return .json(bundle)
            case "rpc/fetch_daily_feature": return .json(feature)
            default: return .emptyArray
            }
        }
    }

    /// `testingGraph` builds `TasteStore` over `UserDefaults.standard` (data lane), so a Discover answer
    /// recorded by one test graph would hide the title in the next. Every graph here starts and ends clean.
    @MainActor
    static func clearHiddenMemory() {
        guard let key = DiscoverHiddenMemory.storageKey(userId: LifecycleFixtures.userA) else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: Pure cards

    static func animeCard(_ id: Int) -> TasteCard? {
        let json = "[" + animeRow(id) + "]"
        guard let card = (try? JSONDecoder().decode([AnimeCard].self, from: Data(json.utf8)))?.first else { return nil }
        return TasteCard(anime: card)
    }

    static func cards(_ name: String) -> [TasteCard] { (sections[name] ?? []).compactMap(animeCard) }
}

// MARK: - The page build (R2, D5, D7, D16)

@Suite("Discover usability: the page build")
@MainActor
struct DiscoverPageBuildTests {
    typealias Sections = DiscoverIssueSections

    private func stem(_ card: TasteCard) -> Set<DiscoverFranchiseKey> {
        if let stem = DiscoverFranchiseStem.stem(card.media.title) { return [.stem(card.key.kind, stem)] }
        return [.component(card.key.kind, card.key.id)]
    }

    private func sources(shown: [Sections.Section: Int] = [:]) -> [DiscoverIssueBuilder.Source] {
        let order: [(Sections.Section, String)] = [(.newToYou, "new_to_you"), (.currentSeason, "current_season"),
                                                   (.essentials, "essentials"), (.trending, "trending"), (.classics, "classics")]
        return order.map { section, name in
            DiscoverIssueBuilder.Source(section: section, cards: DUFixture.cards(name),
                                        shown: shown[section] ?? Sections.shownCount(section, issue: .all, trioColumns: 3, indexRows: 3))
        }
    }

    private func build(hidden: Set<MediaKey> = [], notInterested: Set<MediaKey> = [],
                       owned: [MediaKey: ListStatus] = [:], cap: Int = 6) -> DiscoverIssueBuild {
        DiscoverIssueBuilder.build(lead: DUFixture.animeCard(3), sources: sources(), hiddenKeys: hidden.union(notInterested),
                                   notInterested: notInterested, owned: { owned[$0] }, franchise: stem, issue: .all, cap: cap)
    }

    @Test("No franchise twice on the page: Attack on Titan stays in Essentials, one Demon Slayer in Trending, the lead's Mushishi leaves This season")
    func noRepeats() throws {
        let built = build()
        var seen: Set<DiscoverFranchiseKey> = []
        let allCards = [built.lead].compactMap { $0 } + built.sections.flatMap(\.cards)
        for card in allCards {
            let keys = stem(card)
            #expect(seen.isDisjoint(with: keys), "\(card.media.title) repeats a franchise")
            seen.formUnion(keys)
        }
        let aot = MediaKey(kind: .anime, id: 1)
        #expect(built.built(.essentials)?.cards.contains { $0.key == aot } == true, "Essentials keeps its canon (D5)")
        #expect(built.built(.newToYou)?.cards.contains { $0.key == aot } == false)
        let trending = try #require(built.built(.trending)).cards.map(\.key.id)
        #expect(trending.filter { $0 == 4 || $0 == 5 }.count == 1, "two Demon Slayer entries side by side → one")
        #expect(built.lead?.key == MediaKey(kind: .anime, id: 3))
        #expect(built.built(.currentSeason)?.cards.contains { $0.key.id == 3 } == false)
    }

    @Test("Each section claims shown + 6 reserve; See all counts the rest after the same rules")
    func reserveAndTotals() throws {
        let built = build()
        let ntY = try #require(built.built(.newToYou))
        #expect(ntY.cards.count == min(4 + DiscoverIssueLayout.reserve, 11), "AoT went to Essentials")
        // "See all {n}" counts what the See all page draws: the section's own list after the rules,
        // not after other sections' claims (See all is its own page, so AoT is on it).
        #expect(ntY.total == 12)
        #expect(ntY.total == ntY.ownCards.count)
        #expect(ntY.ownCards.contains { $0.key == MediaKey(kind: .anime, id: 1) })
        #expect(!ntY.refinePool.contains { $0.key == MediaKey(kind: .anime, id: 1) }, "a refinement never draws another section's title")
        let essentials = try #require(built.built(.essentials))
        #expect(essentials.cards.count == 3 + 6)
        #expect(essentials.total == 11 - 0)
    }

    @Test("Owned: hidden in New to you, kept (marked) in Essentials and Trending")
    func ownedRule() throws {
        let odd = MediaKey(kind: .anime, id: 15)
        let fma = MediaKey(kind: .anime, id: 10)
        let built = build(owned: [odd: .planning, fma: .completed])
        #expect(built.built(.newToYou)?.cards.contains { $0.key == odd } == false)
        #expect(built.built(.essentials)?.cards.contains { $0.key == fma } == true)
        #expect(Sections.Section.newToYou.ownedRule == .hide)
        #expect(Sections.Section.becauseYou.ownedRule == .hide)
        #expect(Sections.Section.mangaNewToYou.ownedRule == .hide)
        for section in [Sections.Section.essentials, .trending, .currentSeason, .classics, .tonightShelf, .hiddenGem] {
            #expect(section.ownedRule == .mark)
        }
    }

    @Test("Hidden titles are out; Not interested hides the franchise (D16), Seen it only the title")
    func hiddenRules() throws {
        let slayer = MediaKey(kind: .anime, id: 4)
        let notInterested = build(notInterested: [slayer])
        let trending = try #require(notInterested.built(.trending)).cards.map(\.key.id)
        #expect(!trending.contains(4) && !trending.contains(5), "the whole Demon Slayer franchise leaves")
        let seen = build(hidden: [slayer])
        let seenTrending = try #require(seen.built(.trending)).cards.map(\.key.id)
        #expect(!seenTrending.contains(4))
        #expect(seenTrending.contains(5), "Seen it is title-only: the later season can appear")
        // Within the build, a Not interested on one title hides its franchise-mates live (D16).
        let live = build()
        #expect(live.isFranchiseHidden(MediaKey(kind: .anime, id: 5), notInterested: { $0 == slayer }),
                "Not interested on one Demon Slayer hides the other at once (D16)")
        #expect(!live.isFranchiseHidden(MediaKey(kind: .anime, id: 6), notInterested: { $0 == slayer }))
    }

    @Test("A hide removes the title and the section's reserve slides up; other sections keep their claims")
    func refillFromReserve() throws {
        let built = build()
        let ntY = try #require(built.built(.newToYou))
        let shown = Array(ntY.cards.prefix(4)).map(\.key)
        let hiddenKey = shown[1]
        let after = ntY.cards.filter { $0.key != hiddenKey }
        #expect(after.prefix(4).map(\.key) == [shown[0], shown[2], shown[3], ntY.cards[4].key])
        // The other sections are untouched: claims are fixed per build (R8).
        #expect(built.built(.essentials)?.cards.map(\.key) == build().built(.essentials)?.cards.map(\.key))
    }

    @Test("Live hides (R5): the reserve slides up, See all loses the title, an emptied section leaves, D16 franchise-wide")
    func liveHides() throws {
        let built = build()
        let ntY = try #require(built.built(.newToYou))
        let hiddenKey = ntY.cards[1].key
        let visible = built.visibleSections(isHidden: { $0 == hiddenKey }, notInterested: { _ in false })
        let after = try #require(visible.first { $0.section == .newToYou })
        #expect(after.cards.prefix(4).map(\.key) == [ntY.cards[0].key, ntY.cards[2].key, ntY.cards[3].key, ntY.cards[4].key],
                "the reserve slides up")
        #expect(after.total == ntY.total - 1)
        #expect(visible.map(\.section) == built.sections.map(\.section), "no section moves (R8)")
        #expect(visible.first { $0.section == .essentials }?.cards.map(\.key) == built.built(.essentials)?.cards.map(\.key))

        // Every title of a section hidden: it leaves the page; the cap is not refilled mid-visit.
        let classics = Set(try #require(built.built(.classics)).cards.map(\.key))
        let emptied = built.visibleSections(isHidden: { classics.contains($0) }, notInterested: { _ in false })
        #expect(!emptied.contains { $0.section == .classics })
        #expect(emptied.count == built.sections.count - 1)

        // Not interested on one title hides a claimed franchise-mate anywhere on the page, live (D16).
        let mates = DiscoverIssueBuilder.build(
            lead: nil,
            sources: [DiscoverIssueBuilder.Source(section: .trending, cards: DUFixture.cards("trending"), shown: 10)],
            hiddenKeys: [], notInterested: [], owned: { _ in nil }, franchise: { card in
                // Both Demon Slayer entries share the stem key: claimed once, hidden together (D16).
                card.key.id == 4 || card.key.id == 5 ? [.component(.anime, card.key.id), .stem(.anime, "demon slayer")]
                                                       : [.component(.anime, card.key.id)]
            }, issue: .all)
        let claimed = try #require(mates.built(.trending)).cards.map(\.key.id)
        #expect(claimed.contains(4) && !claimed.contains(5), "one franchise claimed once")
        let slayer = MediaKey(kind: .anime, id: 4)
        #expect(mates.isLiveHidden(MediaKey(kind: .anime, id: 5), isHidden: { _ in false }, notInterested: { $0 == slayer }))
        #expect(!mates.isLiveHidden(MediaKey(kind: .anime, id: 43), isHidden: { _ in false }, notInterested: { $0 == slayer }))

        // A hidden Hidden gem leaves with its section.
        let gemCard = try #require(DUFixture.animeCard(7))
        let gem = DiscoverIssueBuilder.build(lead: nil, sources: [DiscoverIssueBuilder.Source(section: .hiddenGem, cards: [gemCard], shown: 1)],
                                             hiddenKeys: [], notInterested: [], owned: { _ in nil }, franchise: stem, issue: .anime)
        #expect(gem.visibleSections(isHidden: { _ in false }, notInterested: { _ in false }).count == 1)
        #expect(gem.visibleSections(isHidden: { $0 == gemCard.key }, notInterested: { _ in false }).isEmpty)
    }

    @Test("visit_end reports deltas, so a resumed visit never double-counts")
    func tallyDeltas() {
        let first = DiscoverVisitSession.Tally(taps: 5, plans: 2, hides: 1, seen: 0)
        let later = DiscoverVisitSession.Tally(taps: 8, plans: 2, hides: 2, seen: 1)
        #expect(later.minus(first) == DiscoverVisitSession.Tally(taps: 3, plans: 0, hides: 1, seen: 1))
        #expect(first.minus(later) == DiscoverVisitSession.Tally())
    }

    @Test("The cap counts sections that still hold titles after dedupe; the dropped ones become More lists")
    func capAfterDedupe() {
        let built = build(cap: 3)
        #expect(built.sections.map(\.section) == [.newToYou, .currentSeason, .essentials])
        #expect(built.dropped == [.trending, .classics])
        let empty = DiscoverIssueBuilder.build(
            lead: nil,
            sources: [DiscoverIssueBuilder.Source(section: .essentials, cards: DUFixture.cards("essentials"), shown: 3),
                      DiscoverIssueBuilder.Source(section: .classics, cards: DUFixture.cards("essentials"), shown: 3)],
            hiddenKeys: [], notInterested: [], owned: { _ in nil }, franchise: stem, issue: .anime, reserve: 20)
        #expect(empty.sections.map(\.section) == [.essentials], "a section emptied by claims leaves the page")
    }
}

// MARK: - The issue (R1, R7, §5.10, §8)

@Suite("Discover usability: the issue")
@MainActor
struct DiscoverIssueTests {
    typealias Sections = DiscoverIssueSections

    private func full(_ issue: Sections.Issue, realm: Bool, becauseYou: Bool = false) -> Sections.Inputs {
        Sections.Inputs(issue: issue, realmRails: realm, newToYou: true, becauseYou: becauseYou, tonightShelf: true,
                        essentials: true, hiddenGemKind: issue == .manga ? .manga : .anime, mangaNewToYou: true, trending: true,
                        essentialsManga: true, classics: true, currentSeason: true, topRated: true, newlyAdded: true,
                        classicsManga: true, trendingManga: true, topRatedManga: true, newlyAddedManga: true)
    }

    @Test("Every section has exactly one purpose line in both languages (R1)")
    func everySectionHasPurpose() {
        for german in [false, true] {
            for section in Sections.Section.allCases {
                let line = Sections.purpose(section, airingToday: 3, essentials: 11, essentialsManga: 8,
                                            shelfBlurb: nil, german: german)
                #expect(!line.isEmpty, "\(section) has no purpose")
                #expect(!line.contains("\n"))
                #expect(line.count <= 90, "\(section) runs past two lines: \(line)")
            }
        }
        #expect(Sections.purpose(.trending, airingToday: 0, essentials: 0, essentialsManga: 0, shelfBlurb: nil, german: false)
                == "What anime fans are watching right now.")
        #expect(!Sections.purpose(.trending, airingToday: 0, essentials: 0, essentialsManga: 0, shelfBlurb: nil, german: false)
                    .contains("Kuro"), "D15: never \"on Kuro\"")
        #expect(Sections.purpose(.currentSeason, airingToday: 3, essentials: 0, essentialsManga: 0, shelfBlurb: nil, german: false)
                == "Airing now. 3 new episodes out today.")
        #expect(Sections.purpose(.currentSeason, airingToday: 0, essentials: 0, essentialsManga: 0, shelfBlurb: nil, german: true)
                == "Was diese Season läuft.")
        #expect(Sections.purpose(.essentials, airingToday: 0, essentials: 11, essentialsManga: 0, shelfBlurb: nil, german: false)
                == "11 titles to know anime by. Our order, not a ranking.")
        #expect(Sections.purpose(.tonightShelf, airingToday: 0, essentials: 0, essentialsManga: 0,
                                 shelfBlurb: "Soft, slow stories.", german: false) == "Soft, slow stories.")
    }

    @Test("Cap and More lists: at most six on All, Anime and Manga with the flags on and off (R7, D7)")
    func capAndMoreLists() {
        for issue in Sections.Issue.allCases {
            for realm in [false, true] {
                let main = Sections.main(full(issue, realm: realm))
                #expect(main.count <= DiscoverIssueLayout.sectionCap, "\(issue) realm \(realm): \(main.count) sections")
            }
        }
        #expect(Sections.main(full(.all, realm: false)) == [.newToYou, .currentSeason, .essentials, .mangaNewToYou, .trending, .classics])
        #expect(Sections.main(full(.all, realm: true)) == [.newToYou, .tonightShelf, .currentSeason, .essentials, .hiddenGem, .trending])
        #expect(Sections.main(full(.anime, realm: true)) == [.newToYou, .tonightShelf, .currentSeason, .essentials, .hiddenGem, .trending])
        #expect(Sections.main(full(.manga, realm: true)) == [.mangaNewToYou, .essentialsManga, .hiddenGem, .trendingManga, .classicsManga])
        // Nothing becomes unreachable: every dropped section is a More list.
        let dropped = Sections.cap(Sections.candidates(full(.anime, realm: true))).dropped
        #expect(dropped == [.classics])
        #expect(Sections.moreLists(full(.anime, realm: true), dropped: dropped).contains(.route(.animeClassics)))
        // The drop order beyond the shipped lists: Hidden gem, then Tonight's shelf.
        #expect(Sections.cap([.newToYou, .tonightShelf, .currentSeason, .essentials, .hiddenGem, .trending], limit: 4).dropped
                == [.tonightShelf, .hiddenGem])
        #expect(Sections.moreLists(full(.all, realm: false), dropped: [.hiddenGem, .tonightShelf]).suffix(2) == [.hiddenGem, .tonightShelf])
    }

    @Test("Shown counts: trio 1 + columns, This season's row, index rows, rails ten, the gem one")
    func shownCounts() {
        #expect(Sections.shownCount(.newToYou, issue: .all, trioColumns: 3, indexRows: 3) == 4)
        #expect(Sections.shownCount(.currentSeason, issue: .all, trioColumns: 3, indexRows: 3) == 3)
        #expect(Sections.shownCount(.essentials, issue: .anime, trioColumns: 3, indexRows: 5) == 5)
        #expect(Sections.shownCount(.mangaNewToYou, issue: .all, trioColumns: 3, indexRows: 3) == 10)
        #expect(Sections.shownCount(.mangaNewToYou, issue: .manga, trioColumns: 3, indexRows: 5) == 4)
        #expect(Sections.shownCount(.trending, issue: .all, trioColumns: 3, indexRows: 3) == 10)
        #expect(Sections.shownCount(.hiddenGem, issue: .all, trioColumns: 3, indexRows: 3) == 1)
        #expect(DiscoverIssueLayout.reserve == 6)
    }

    @Test("Section ids are the route ids plus tonightShelf and hiddenGem")
    func sectionIds() {
        #expect(Sections.Section.newToYou.id == "animeNewToYou")
        #expect(Sections.Section.essentialsManga.id == "mangaEssentials")
        #expect(Sections.Section.tonightShelf.id == "tonightShelf")
        #expect(Sections.Section.hiddenGem.id == "hiddenGem")
        #expect(Set(Sections.Section.allCases.map(\.id)).count == Sections.Section.allCases.count)
        #expect(Sections.Section.essentials.isCanon && Sections.Section.essentialsManga.isCanon)
        #expect(!Sections.Section.trending.isCanon)
    }

    @Test("Pinned words EN / DE (§8): Essentials / Kanon, Trending / Im Trend; Manga beside New on All")
    func pinnedWords() {
        let en = [Sections.Section.newToYou, .currentSeason, .essentials, .mangaNewToYou, .trending, .classics]
            .map { DiscoverIssueCopy.pinnedWord($0, issue: .all, german: false) }
        #expect(en == ["New", "Season", "Essentials", "Manga", "Trending", "Classics"])
        let de = [Sections.Section.newToYou, .currentSeason, .essentials, .mangaNewToYou, .trending, .classics]
            .map { DiscoverIssueCopy.pinnedWord($0, issue: .all, german: true) }
        #expect(de == ["Neu", "Season", "Kanon", "Manga", "Im Trend", "Klassiker"])
        #expect(DiscoverIssueCopy.pinnedWord(.mangaNewToYou, issue: .manga, german: false) == "New")
        #expect(DiscoverIssueCopy.pinnedWord(.tonightShelf, german: true) == "Regal")
        #expect(DiscoverIssueCopy.pinnedWord(.hiddenGem, german: false) == "Gem")
        #expect(DiscoverPinnedState.states(count: 4, current: 2) == [.passed, .passed, .current, .ahead])
        #expect(DiscoverPinnedState.states(count: 2, current: nil) == [.ahead, .ahead])
    }

    @Test("Trending refine words (D10): the shipped ≤ 13 / > 50 rules, \"Fertig erschienen\" in German")
    func refineWords() {
        #expect(DiscoverRailFilter.allCases.map { DiscoverIssueCopy.refineWord($0, german: false) }
                == ["Any length", "Up to 13 episodes", "Over 50 episodes", "Finished"])
        #expect(DiscoverRailFilter.allCases.map { DiscoverIssueCopy.refineWord($0, german: true) }
                == ["Jede Länge", "Bis 13 Folgen", "Über 50 Folgen", "Fertig erschienen"])
        // The words follow the shipped rules exactly.
        #expect(DiscoverRailFilter.short.includes(episodes: 13, statusRaw: nil))
        #expect(!DiscoverRailFilter.short.includes(episodes: 14, statusRaw: nil))
        #expect(!DiscoverRailFilter.long.includes(episodes: 50, statusRaw: nil))
        #expect(DiscoverRailFilter.long.includes(episodes: 51, statusRaw: nil))
        // DiscoverRailFilter's own labels stay for its other users (EntityRefineWords).
        #expect(DiscoverRailFilter.short.title(german: false) == "Short")
    }

    @Test("Kind kicker on All (§5.11) and the status word on owned index rows (R2)")
    func kickerAndStatus() {
        #expect(DiscoverIssueCopy.kindKicker(.anime) == "ANIME")
        #expect(DiscoverIssueCopy.kindKicker(.manga) == "MANGA")
        #expect(DiscoverIssueCopy.kindSpoken(.manga, title: "Berserk") == "Manga: Berserk")
        #expect(DiscoverCardSpoken.label(title: "Frieren", kind: .anime, kindKicker: true, line: "2023 · TV", isNew: false)
                == "Anime: Frieren, 2023 · TV")
        #expect(DiscoverCardSpoken.label(title: "Frieren", kind: .anime, kindKicker: false, line: nil, isNew: false) == "Frieren")
        #expect(DiscoverIssueCopy.statusWord(.current, progress: 5, kind: .anime, german: false) == "Watching · Ep. 5")
        #expect(DiscoverIssueCopy.statusWord(.current, progress: 5, kind: .anime, german: true) == "Schaue ich · F. 5")
        #expect(DiscoverIssueCopy.statusWord(.completed, progress: 12, kind: .anime, german: true) == "Abgeschlossen")
        #expect(DiscoverIssueCopy.statusWord(.planning, progress: 0, kind: .manga, german: false) == "Planned")
    }

    @Test("NEW markers: the tab and the heading line, weekday under a week, \"last visit\" beyond")
    func newCopy() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let tuesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12)))
        let thursday = tuesday.addingTimeInterval(2 * 86_400)
        #expect(DiscoverIssueCopy.newSince(3, lastVisit: tuesday, now: thursday, german: false) == "3 new since Tue")
        #expect(DiscoverIssueCopy.newSince(3, lastVisit: tuesday, now: thursday, german: true) == "3 neu seit Dienstag")
        // A return later the same day never names today's weekday.
        #expect(DiscoverIssueCopy.newSince(3, lastVisit: tuesday, now: tuesday.addingTimeInterval(2 * 3600), german: false)
            == "3 new since your last visit")
        #expect(DiscoverIssueCopy.newSince(3, lastVisit: tuesday, now: tuesday.addingTimeInterval(2 * 3600), german: true)
            == "3 neu seit deinem letzten Besuch")
        #expect(DiscoverIssueCopy.newSince(2, lastVisit: tuesday, now: tuesday.addingTimeInterval(8 * 86_400), german: false)
                == "2 new since your last visit")
        #expect(DiscoverIssueCopy.newTab(german: false) == "NEW")
        #expect(DiscoverIssueCopy.newTab(german: true) == "NEU")
    }

    @Test("The end (§5.7): tally, what you did today (only parts above zero), Search and More lists words")
    func endCopy() {
        #expect(DiscoverIssueCopy.endTitle(german: false) == "You're caught up for today.")
        #expect(DiscoverIssueCopy.endTitle(german: true) == "Für heute bist du durch.")
        #expect(DiscoverIssueCopy.endTally(sections: 6, titles: 38, german: false) == "6 sections, 38 titles.")
        #expect(DiscoverIssueCopy.endTally(sections: 6, titles: 38, german: true) == "6 Rubriken, 38 Titel.")
        #expect(DiscoverIssueCopy.endActions(planned: 2, hidden: 1, seen: 1, german: false)
                == "You planned 2, hid 1 and marked 1 as seen.")
        #expect(DiscoverIssueCopy.endActions(planned: 2, hidden: 1, seen: 1, german: true)
                == "2 vorgemerkt, 1 ausgeblendet und 1 als gesehen markiert.")
        #expect(DiscoverIssueCopy.endActions(planned: 0, hidden: 2, seen: 0, german: false) == "You hid 2.")
        #expect(DiscoverIssueCopy.endActions(planned: 0, hidden: 0, seen: 0, german: false) == nil)
        #expect(DiscoverIssueCopy.endTomorrow(german: false) == "A new issue tomorrow morning.")
        #expect(DiscoverIssueCopy.searchKicker(german: true) == "Etwas Bestimmtes")
        #expect(DiscoverIssueCopy.moreListsEyebrow(german: false) == "More lists")
        #expect(DiscoverIssueCopy.headerScrollToTop(german: false) == "Discover. Scroll to top")
        #expect(DiscoverIssueCopy.headerScrollToTop(german: true) == "Entdecken. Nach oben")
    }

    @Test("Mood keys (§5.4): four with a seed, three without; one column at accessibility sizes or compact German")
    func moodKeys() {
        #expect(DiscoverMoodKeys.moods(hasSeed: true) == [.short, .cozy, .intense, .likeLastLoved])
        #expect(DiscoverMoodKeys.moods(hasSeed: false) == [.short, .cozy, .intense])
        #expect(DiscoverMoodKeys.columns(accessibility: false, compact: false, german: true) == 2)
        #expect(DiscoverMoodKeys.columns(accessibility: true, compact: false, german: false) == 1)
        #expect(DiscoverMoodKeys.columns(accessibility: false, compact: true, german: true) == 1)
        #expect(DiscoverIssueCopy.moodTitle(.likeLastLoved, likeTitle: "Frieren", german: false) == "Like Frieren")
        #expect(DiscoverIssueCopy.moodTitle(.likeLastLoved, likeTitle: "Frieren", german: true) == "Wie Frieren")
        #expect(DiscoverIssueCopy.moodSubtitle(.short, german: false) == "An evening or a weekend")
        #expect(DiscoverIssueCopy.moodsEyebrow(german: true) == "Lust auf")
        #expect(DiscoverMoodRoute.pageID(.cozy) == "discover:mood:cozy")
    }

    @Test("Progress hook (§5.9): Completed + Seen it count, Not interested leaves the total, Watching is half")
    func progressHook() {
        let items = (1...8).map { (key: MediaKey(kind: .anime, id: $0), title: "T\($0)") }
        let status: [Int: ListStatus] = [1: .completed, 2: .completed, 3: .current, 4: .planning]
        let hidden: [Int: DiscoverFeedback] = [5: .seenIt, 6: .notInterested]
        let model = DiscoverProgressModel.make(items: items, status: { status[$0.id] }, hidden: { hidden[$0.id] })
        #expect(model.seen == 3)
        #expect(model.total == 7)
        #expect(model.underWay == "T3")
        #expect(model.remaining == 4)
        #expect(model.segments == [.done, .done, .half, .open, .done, .open, .open])
        #expect(model.shows)
        let none = DiscoverProgressModel.make(items: items, status: { _ in nil }, hidden: { _ in nil })
        #expect(!none.shows, "the hook shows only once k ≥ 1")
        #expect(DiscoverIssueCopy.progressHead(seen: 3, of: 8, manga: false, german: false) == "You've seen 3 of 8.")
        #expect(DiscoverIssueCopy.progressHead(seen: 3, of: 8, manga: true, german: true) == "3 von 8 gelesen.")
        #expect(DiscoverIssueCopy.progressUnderWay("Monster", german: true) == "Monster läuft gerade.")
        #expect(DiscoverIssueCopy.progressToGo(5, german: false) == "5 to go.")
        #expect(DiscoverIssueCopy.progressSpoken(seen: 3, of: 8, manga: false, german: false) == "You've seen 3 of 8 essential anime")
    }

    @Test("Scroll geometry: passed the band, half visible, the current section")
    func geometry() {
        let band = DiscoverPinnedIndex.bandHeight
        let below = DiscoverSectionGeometry.make(frame: CGRect(x: 0, y: 900, width: 350, height: 400), viewport: 800, band: band)
        #expect(!below.passedTop && !below.halfVisible)
        let half = DiscoverSectionGeometry.make(frame: CGRect(x: 0, y: 500, width: 350, height: 400), viewport: 800, band: band)
        #expect(!half.passedTop && half.halfVisible)
        let top = DiscoverSectionGeometry.make(frame: CGRect(x: 0, y: 20, width: 350, height: 400), viewport: 800, band: band)
        #expect(top.passedTop && top.halfVisible)
        let tall = DiscoverSectionGeometry.make(frame: CGRect(x: 0, y: -200, width: 350, height: 2000), viewport: 800, band: band)
        #expect(tall.halfVisible, "a section taller than the screen counts once it fills half of it")
        let order = ["a", "b", "c"]
        #expect(DiscoverSectionGeometry.current(order: order, geometry: ["a": top, "b": top, "c": below]) == "b")
        #expect(DiscoverSectionGeometry.current(order: order, geometry: ["a": below]) == nil)
        #expect(DiscoverVisitSession.depthBucket(offset: 0, visible: 800, content: 2400) == 3)
        #expect(DiscoverVisitSession.depthBucket(offset: 1600, visible: 800, content: 2400) == 10)
        #expect(DiscoverVisitSession.dwellBucket(5) == "lt10s")
        #expect(DiscoverVisitSession.dwellBucket(30) == "10to60s")
        #expect(DiscoverVisitSession.dwellBucket(120) == "1to5m")
        #expect(DiscoverVisitSession.dwellBucket(600) == "gt5m")
    }
}

// MARK: - Visit memory (§5.8, D18)

@Suite("Discover usability: visit memory and NEW marks")
@MainActor
struct DiscoverVisitTests {
    private let a = MediaKey(kind: .anime, id: 1)
    private let b = MediaKey(kind: .anime, id: 2)
    private let c = MediaKey(kind: .anime, id: 3)

    private func defaults() throws -> (UserDefaults, String) {
        let suite = "kuro.tests.du-visits.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test("The first visit ever shows no NEW; the second marks only titles absent from the last snapshot")
    func secondVisit() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var session = DiscoverVisitSession()
        let began = session.begin(userId: "USER-A", defaults: store, now: start)
        #expect(began)
        #expect(session.baseline.newKeys(section: "animeNewToYou", shown: [a, b]).isEmpty, "first visit: none")
        session.seen["animeNewToYou"] = [a, b]
        let summary = session.end(defaults: store, now: start.addingTimeInterval(60))
        #expect(summary?.sectionsSeen == 1)

        // A relaunch (a new session over the same storage) more than 30 minutes later.
        var next = DiscoverVisitSession()
        let nextBegan = next.begin(userId: "user-a", defaults: store, now: start.addingTimeInterval(3_600))
        #expect(nextBegan)
        #expect(next.baseline.newKeys(section: "animeNewToYou", shown: [a, b, c]) == [c])
        #expect(next.baseline.newKeys(section: "animeTrending", shown: [a]).isEmpty, "no snapshot: no NEW")
    }

    @Test("D18: back within 30 minutes resumes the visit (marks stay); after 30 minutes a new visit begins")
    func thirtyMinutes() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var session = DiscoverVisitSession()
        _ = session.begin(userId: "u", defaults: store, now: start)
        session.seen["s"] = [a]
        _ = session.end(defaults: store, now: start.addingTimeInterval(10))
        let resumed = session.begin(userId: "u", defaults: store, now: start.addingTimeInterval(20 * 60))
        #expect(!resumed, "resumed")
        _ = session.end(defaults: store, now: start.addingTimeInterval(21 * 60))
        let fresh = session.begin(userId: "u", defaults: store, now: start.addingTimeInterval(52 * 60))
        #expect(fresh, "a new visit")
        #expect(DiscoverVisitLedger.startsVisit(firstThisLaunch: true, lastEnd: start, now: start))
        #expect(!DiscoverVisitLedger.startsVisit(firstThisLaunch: false, lastEnd: start, now: start.addingTimeInterval(29 * 60)))
    }

    @Test("Each account keeps its own snapshot (hashed key, kinds and ids only); a section not reached keeps its old one")
    func perAccount() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var ledger = DiscoverVisitLedger()
        ledger.commit(seen: ["x": [a, a, b]], at: now)
        #expect(ledger.sections["x"]?.keys.count == 2, "unique keys")
        ledger.commit(seen: ["y": [c]], at: now.addingTimeInterval(60))
        #expect(ledger.sections["x"] != nil, "a section not seen keeps its snapshot")
        ledger.save(defaults: store, userId: "Alice")
        #expect(DiscoverVisitLedger.load(defaults: store, userId: "alice") == ledger)
        #expect(DiscoverVisitLedger.load(defaults: store, userId: "bob").sections.isEmpty)
        let key = DiscoverVisitLedger.storageKey(userId: "Alice")
        #expect(key.hasPrefix("kuro.discover.visits.") && key.count == "kuro.discover.visits.".count + 16)
        #expect(!key.lowercased().contains("alice"))
        DiscoverVisitLedger.remove(defaults: store, userId: "alice")
        #expect(DiscoverVisitLedger.load(defaults: store, userId: "alice").sections.isEmpty)
        var big = DiscoverVisitLedger()
        big.commit(seen: ["z": (1...200).map { MediaKey(kind: .manga, id: $0) }], at: now)
        #expect(big.sections["z"]?.keys.count == DiscoverVisitLedger.capacity)
    }
}

// MARK: - Feedback (R4, R5, D12)

@Suite("Discover usability: page feedback", .serialized)
@MainActor
struct DiscoverPageFeedbackTests {
    init() { DUFixture.clearHiddenMemory() }

    @Test("Lane B's controller records the answer; the page tallies it, and Undo takes it back once")
    func hideAndUndoTallies() async throws {
        let harness = try DCDiscoverHarness(responder: { _ in .emptyArray })
        await harness.signIn()
        let taste = harness.graph.taste
        let page = DiscoverPageFeedback()
        let hides = DiscoverFeedbackController(holdSeconds: 60, assistiveTechnologyRunning: { false })
        hides.onUndone = { page.noteUndone($0) }
        let card = try #require(DUFixture.animeCard(15))
        var hiddenCards: [TasteCard] = []
        page.onHidden = { _, hidden in hiddenCards.append(hidden) }

        let receipt = try #require(hides.record(.notInterested, for: card.media, taste: taste, german: false))
        page.noteHidden(receipt, card: card)
        #expect(taste.isHiddenOnDiscover(card.key), "R5: removed before any network answer")
        #expect(page.hidden == 1 && page.taps == 1)
        #expect(hiddenCards.map(\.key) == [card.key])
        #expect(hides.toast?.receipt != nil)

        #expect(hides.undo(taste: taste, german: false) != nil)
        #expect(!taste.isHiddenOnDiscover(card.key))
        #expect(page.hidden == 0, "Undo takes the tally back")
        #expect(hides.undo(taste: taste, german: false) == nil, "Undo reverses exactly once")
        #expect(page.hidden == 0)

        let seen = try #require(DUFixture.animeCard(16))
        let seenReceipt = try #require(hides.record(.seenIt, for: seen.media, taste: taste, german: false))
        page.noteHidden(seenReceipt, card: seen)
        #expect(page.seen == 1 && page.taps == 2)
        page.resetSession()
        #expect(page.seen == 0 && page.hidden == 0 && page.taps == 0 && page.planned == 0)
        await harness.tearDown()
        DUFixture.clearHiddenMemory()
    }

    @Test("The preview's reason line carries its prefix once (the page passes bare reason words)")
    func reasonPrefixOnce() {
        let line = DiscoverMenuCopy.whyItsHere(DiscoverMenuCopy.Reason.canon.text(german: false), german: false)
        #expect(line == "Why it's here: in our canon.")
        let de = DiscoverMenuCopy.whyItsHere(DiscoverMenuCopy.Reason.closeTo("Frieren").text(german: true), german: true)
        #expect(de == "Warum es hier ist: nah an Frieren.")
    }

    @Test("Plan results are counted once per token: added, then undone; removed counts a tap only")
    func planResults() {
        let page = DiscoverPageFeedback()
        let key = MediaKey(kind: .anime, id: 25)
        page.notePlanResult(TastePlanController.Result(key: key, outcome: .added, token: 1), viaMenu: false)
        page.notePlanResult(TastePlanController.Result(key: key, outcome: .added, token: 1), viaMenu: false)
        #expect(page.planned == 1 && page.taps == 1, "the same result twice counts once")
        page.notePlanResult(TastePlanController.Result(key: key, outcome: .undone, token: 2), viaMenu: false)
        #expect(page.planned == 0)
        page.notePlanResult(TastePlanController.Result(key: key, outcome: .removed, token: 3), viaMenu: true)
        #expect(page.planned == 0 && page.taps == 2)
        page.notePlanResult(TastePlanController.Result(key: key, outcome: .failed, token: 4), viaMenu: false)
        #expect(page.planned == 0 && page.taps == 2)
        page.noteMenuOpen()
        #expect(page.taps == 3, "an Open from the menu counts for the visit (and the D5 rebuild guard)")
    }
}


// MARK: - Review fixes (2026-11-04 integrator)

@Suite("Discover usability: review fixes (counts, sequels, refine, visits, copy)")
@MainActor
struct DiscoverReviewFixTests {
    private func card(_ id: Int, _ title: String, episodes: Int? = 12, status: String = "FINISHED") throws -> TasteCard {
        let json = """
        {"id":\(id),"title_english":"\(title)","title_romaji":null,"title_native":null,
         "cover_image_large":"https://visual-fixture.invalid/a.jpg","cover_image_medium":null,"banner_image":null,
         "format":"TV","status":"\(status)","episode_count":\(episodes.map(String.init) ?? "null"),"season_year":2020,
         "start_date_year":2020,"average_score":80,"popularity":1000,"trending":1,"favourites":1,"genres":["Drama"]}
        """
        return TasteCard(anime: try JSONDecoder().decode(AnimeCard.self, from: Data(json.utf8)))
    }

    private func stem(_ card: TasteCard) -> Set<DiscoverFranchiseKey> {
        if let stem = DiscoverFranchiseStem.stem(card.media.title) { return [.stem(card.key.kind, stem)] }
        return [.component(card.key.kind, card.key.id)]
    }

    @Test("Sequel words: explicit seasons, parts, finals, R2, roman numerals and arcs; never a bare number")
    func sequelWords() {
        for title in ["Attack on Titan Final Season", "Attack on Titan Season 3 Part 2", "HAIKYU!! 3rd Season",
                      "Code Geass: Lelouch of the Rebellion R2", "Demon Slayer: Kimetsu no Yaiba Swordsmith Village Arc",
                      "Overlord II", "Mob Psycho 100 Season 2", "Attack on Titan: The Final Season"] {
            #expect(DiscoverSequel.isSequel(title), "\(title) is a later entry")
        }
        for title in ["Attack on Titan", "Kaiju No. 8", "Mob Psycho 100", "Code Geass: Lelouch of the Rebellion",
                      "Frieren: Beyond Journey's End", "Steins;Gate", "Season of Love", "Arcane"] {
            #expect(!DiscoverSequel.isSequel(title), "\(title) is not a sequel")
        }
    }

    @Test("Personal sections leave sequels out (a first-timer never gets season 3); editorial sections keep them")
    func sequelsOutOfPersonalSections() throws {
        let items = try [card(1, "Attack on Titan Final Season"), card(2, "Odd Taxi"), card(3, "HAIKYU!! 3rd Season")]
        let compose: (DiscoverOwnedPolicy) -> [Int] = { policy in
            DiscoverPageComposer.compose(
                [DiscoverSectionInput(id: "s", policy: policy, items: items, displayCount: 10)],
                key: \.key, franchiseKeys: { [.component(.anime, $0.key.id)] }, isHidden: { _ in false },
                ownedStatus: { _ in nil }, isSequel: { DiscoverSequel.isSequel($0.media.title) })
                .first?.items.map(\.item.key.id) ?? []
        }
        #expect(compose(.hide) == [2])
        #expect(compose(.mark) == [1, 2, 3])
    }

    @Test("The tail is deduped within its section only: two seasons in a tail count once, and they never block a later section")
    func tailFranchisesAreLocal() throws {
        let a = try [card(1, "Odd Taxi"), card(2, "Planetes"), card(3, "Planetes Season 2")]
        let b = try [card(4, "Planetes: The Movie")]
        let placed = DiscoverPageComposer.compose(
            [DiscoverSectionInput(id: "a", policy: .mark, items: a, displayCount: 1),
             DiscoverSectionInput(id: "b", policy: .mark, items: b, displayCount: 1)],
            key: \.key, franchiseKeys: stem, isHidden: { _ in false }, ownedStatus: { _ in nil })
        #expect(placed[0].items.map(\.item.key.id) == [1])
        #expect(placed[0].remainingCount == 1, "Planetes and its Season 2 are one series in the tail")
        #expect(placed[1].items.map(\.item.key.id) == [4], "a tail never claims a franchise for the page")
    }

    @Test("The rail refinement draws from the whole unclaimed list and counts the See all matches (R6)")
    func railRefine() throws {
        let claimed = try (1...3).map { try card($0, "Claimed \($0)", episodes: 24) }
        let pool = try claimed + (4...9).map { try card($0, "Pool \($0)", episodes: $0 % 2 == 0 ? 12 : 64) }
        let own = try pool + [card(10, "Elsewhere", episodes: 10)]
        let any = DiscoverRailRefine.make(filter: .all, cards: claimed, total: 10, ownCards: own, refinePool: pool)
        #expect(any.cards.map(\.key.id) == [1, 2, 3])
        #expect(any.total == 10)
        let short = DiscoverRailRefine.make(filter: .short, cards: claimed, total: 10, ownCards: own, refinePool: pool)
        #expect(short.cards.map(\.key.id) == [4, 6, 8], "beyond the claimed cards, never another section's title")
        #expect(short.total == 4, "See all with the chip draws the section's own list: 4, 6, 8 and 10")
        let long = DiscoverRailRefine.make(filter: .long, cards: claimed, total: 10, ownCards: own, refinePool: pool)
        #expect(long.cards.map(\.key.id) == [5, 7, 9])
    }

    @Test("See all opens with the rail's choice selected; Hide my list only where owned titles are kept")
    func seeAllOpening() throws {
        let trending = DiscoverSeeAllSection.of(.animeTrending)
        let short = try #require(DiscoverSeeAllSelection.opening(trending, refine: .short))
        #expect(short.length == .upTo13)
        #expect(short.sort == trending.defaultSort)
        #expect(DiscoverSeeAllSelection.opening(trending, refine: .long)?.length == .over50)
        #expect(DiscoverSeeAllSelection.opening(trending, refine: .finished)?.status == .finished)
        #expect(DiscoverSeeAllSelection.opening(trending, refine: .all) == nil)
        #expect(trending.chipGroups.contains([.hideMyList]))
        #expect(!DiscoverSeeAllSection.of(.animeNewToYou).chipGroups.contains([.hideMyList]))
        #expect(!DiscoverSeeAllSection.of(.mangaNewToYou).chipGroups.contains([.hideMyList]))
        #expect(!DiscoverSeeAllSection.of(.animeBecauseYou).chipGroups.contains([.hideMyList]))
    }

    @Test("The See all number is promised only where See all draws the loaded rows (R1)")
    func exactCounts() {
        for route in [EditorialDiscoverRoute.animeEssentials, .animeClassics, .mangaEssentials, .mangaClassics,
                      .animeBecauseYou, .animeAiringToday] {
            #expect(DiscoverSeeAllSection.of(route).drawsOnlyLoadedRows, "\(route)")
        }
        for route in [EditorialDiscoverRoute.animeTrending, .mangaTrending, .animeTopRated, .animeNewlyAdded,
                      .animeNewToYou, .mangaNewToYou, .animeCurrentSeason] {
            #expect(!DiscoverSeeAllSection.of(route).drawsOnlyLoadedRows, "\(route)")
        }
        #expect(DiscoverIssueCopy.seeAll(nil, german: false) == "See all ›")
        #expect(DiscoverIssueCopy.seeAll(nil, german: true) == "Alle ansehen ›")
        #expect(DiscoverIssueCopy.seeAll(12, german: false) == "See all 12 ›")
        #expect(DiscoverIssueCopy.seeAllSpoken(nil, section: "Trending.", german: false).hasPrefix("See all"))
        let open = DiscoverContents.Entry(id: "a", name: "Trending", count: 11, exact: false)
        #expect(DiscoverContents.trailing(open, german: false) == "")
        #expect(DiscoverIssueCopy.contentsSpoken(name: "Trending", count: nil, german: false) == "Jump to Trending")
    }

    @Test("A new visit on a new rail day reads the new issue; the same day rebuilds; late inputs rebuild only before any action")
    func visitStart() {
        #expect(DiscoverPageRules.visitStart(hasBuilt: true, bundleIsToday: false) == .readNewIssue)
        #expect(DiscoverPageRules.visitStart(hasBuilt: true, bundleIsToday: true) == .rebuild)
        #expect(DiscoverPageRules.visitStart(hasBuilt: false, bundleIsToday: false) == nil)
        #expect(DiscoverPageRules.lateRebuildAllowed(hasBuilt: true, taps: 0, depth: 1))
        #expect(!DiscoverPageRules.lateRebuildAllowed(hasBuilt: true, taps: 1, depth: 0))
        #expect(!DiscoverPageRules.lateRebuildAllowed(hasBuilt: true, taps: 0, depth: 2))
        #expect(!DiscoverPageRules.lateRebuildAllowed(hasBuilt: false, taps: 0, depth: 0))
    }

    @Test("Copy: no doubled medium in the preview kicker, manga answers say read, the tally names the issue's word, the short mood promises no completeness")
    func copyFixes() {
        #expect(DiscoverMenuCopy.previewKicker(kind: .anime, section: "Essential anime.", german: false) == "ESSENTIAL ANIME")
        #expect(DiscoverMenuCopy.previewKicker(kind: .manga, section: "Unverzichtbare Manga", german: true) == "UNVERZICHTBARE MANGA")
        #expect(DiscoverMenuCopy.previewKicker(kind: .anime, section: "New to you.", german: false) == "ANIME · NEW TO YOU")
        #expect(DiscoverMenuCopy.toast(.seenIt, medium: .manga, german: false) == "Marked as read.")
        #expect(DiscoverMenuCopy.toast(.seenIt, medium: .manga, german: true) == "Als gelesen markiert.")
        #expect(DiscoverMenuCopy.toast(.seenIt, medium: .anime, german: false) == "Marked as seen.")
        #expect(DiscoverMenuCopy.Reason.unread.text(german: false) == "unread by you")
        #expect(DiscoverMenuCopy.Reason.unread.text(german: true) == "noch nicht gelesen")
        #expect(DiscoverIssueCopy.endActions(planned: 0, hidden: 0, seen: 2, seenWord: .read, german: false) == "You marked 2 as read.")
        #expect(DiscoverIssueCopy.endActions(planned: 0, hidden: 0, seen: 2, seenWord: .seenOrRead, german: false)
            == "You marked 2 as seen or read.")
        #expect(DiscoverIssueCopy.moodSubtitle(.short, german: true) == "Für einen Abend oder ein Wochenende")
        // The kind kicker on All already says MANGA: the plain manga format word is not repeated.
        #expect(DiscoverIssueCopy.facts(kind: .manga, year: "2018", formatRaw: "MANGA", episodes: nil, chapters: nil,
                                        length: false, german: false, kindShown: true) == "2018")
        #expect(DiscoverIssueCopy.facts(kind: .manga, year: "2018", formatRaw: "MANGA", episodes: nil, chapters: nil,
                                        length: false, german: false) == "2018 · Manga")
    }
}
