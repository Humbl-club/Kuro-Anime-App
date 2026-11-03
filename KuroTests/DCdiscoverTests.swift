//
//  DCdiscoverTests.swift
//  KuroTests
//
//  Discover + Clubs redesign, Discover lane (2026-11-03): the issue's pure rules. Layout (gutter,
//  compact column, switch sizes, art heights, the capped spread, trio and index metrics), the EN/DE
//  copy (opening kicker, tab split, facts, glance caption, contents line, fold, states, See all), the
//  fold's session memory and the page canvas the header paints.
//

import Foundation
import KuroCore
import SwiftUI
import Testing
@testable import Kuro

@Suite("Discover lane (DC): layout")
struct DCDiscoverLayoutTests {
    @Test("Home's gutter (16 at a container ≤ 330) and the compact column (≤ 328)")
    func gutterAndCompact() {
        #expect(DiscoverIssueLayout.gutter(container: 320) == 16)
        #expect(DiscoverIssueLayout.gutter(container: 330) == 16)
        #expect(DiscoverIssueLayout.gutter(container: 331) == 20)
        #expect(DiscoverIssueLayout.gutter(container: 390) == 20)
        #expect(DiscoverIssueLayout.gutter(container: 680) == 20)
        #expect(DiscoverIssueLayout.isCompact(column: 288))
        #expect(DiscoverIssueLayout.isCompact(column: 328))
        #expect(!DiscoverIssueLayout.isCompact(column: 329))
        #expect(!DiscoverIssueLayout.isCompact(column: 350))
        #expect(!DiscoverIssueLayout.isCompact(column: 0), "unmeasured is not compact")
    }

    @Test("Issue switch: 28 pt words, 24 pt in the SE column; the row is at least 50 pt")
    func switchSizing() {
        #expect(DiscoverIssueLayout.switchWordSize(column: 350) == 28)
        #expect(DiscoverIssueLayout.switchWordSize(column: 640) == 28)
        #expect(DiscoverIssueLayout.switchWordSize(column: 288) == 24)
        #expect(DiscoverIssueLayout.switchMinHeight == 50)
    }

    @Test("Cover story art: 2.2 : 1 (159 at 350), the feature and Hidden gem 3.25 : 1 (108 at 350)")
    func artHeights() {
        #expect(DiscoverIssueLayout.artHeight(column: 350, aspect: DiscoverIssueLayout.coverBannerAspect) == 159)
        #expect(DiscoverIssueLayout.artHeight(column: 350, aspect: DiscoverIssueLayout.featureBannerAspect) == 108)
        #expect(DiscoverIssueLayout.artHeight(column: 0, aspect: 2.2) == 0)
    }

    @Test("The cover-only spread: 132 × 198 (104 × 156 compact), never over 220 (P14); the feature's 160")
    func spread() {
        #expect(DiscoverIssueLayout.spreadCover(compact: false) == CGSize(width: 132, height: 198))
        #expect(DiscoverIssueLayout.spreadCover(compact: true) == CGSize(width: 104, height: 156))
        #expect(DiscoverIssueLayout.spreadCover(compact: false).height <= DiscoverIssueLayout.spreadMaxHeight)
        #expect(DiscoverIssueLayout.featureSpreadCover(compact: false) == CGSize(width: 107, height: 160))
        #expect(DiscoverIssueLayout.featureSpreadCover(compact: false).height <= DiscoverIssueLayout.featureSpreadHeight)
        // The panel's copy can only grow the spread, never shrink it below the cover.
        #expect(DiscoverIssueLayout.spreadHeight(cover: CGSize(width: 132, height: 198), panelHeight: 150) == 198)
        #expect(DiscoverIssueLayout.spreadHeight(cover: CGSize(width: 132, height: 198), panelHeight: 210) == 210)
    }

    @Test("Trio: three covers 14 apart, four on the iPad column, two at accessibility sizes")
    func trio() {
        #expect(DiscoverIssueLayout.trioColumns(regularWidth: false, accessibility: false) == 3)
        #expect(DiscoverIssueLayout.trioColumns(regularWidth: true, accessibility: false) == 4)
        #expect(DiscoverIssueLayout.trioColumns(regularWidth: false, accessibility: true) == 2)
        #expect(DiscoverIssueLayout.trioCoverWidth(column: 350, columns: 3) == 107)
        #expect(DiscoverIssueLayout.trioCoverWidth(column: 288, columns: 3) == 86)
        let width = DiscoverIssueLayout.trioCoverWidth(column: 640, columns: 4)
        #expect(width * 4 + DiscoverIssueLayout.trioSpacing * 3 <= 640)
    }

    @Test("Index: five rows, 76 pt tall, the key at least 96 (84 compact); the rail by the edge-peek rule, ten at most")
    func indexAndRail() {
        #expect(DiscoverIssueLayout.indexRows == 5)
        #expect(DiscoverIssueLayout.indexRows(onAll: true) == 3, "All carries both media: three rows, See all for the rest")
        #expect(DiscoverIssueLayout.indexRows(onAll: false) == 5)
        #expect(DiscoverIssueLayout.indexRowMinHeight == 76)
        #expect(DiscoverIssueLayout.indexKeyWidth(compact: false) == 96)
        #expect(DiscoverIssueLayout.indexKeyWidth(compact: true) == 84)
        #expect(DiscoverIssueLayout.footKeyColumn(compact: false) == 112)
        #expect(DiscoverIssueLayout.footKeyColumn(compact: true) == 96)
        // Details-songs spec §5.1: 100 × 150 at 390 (column 350 + gutter 20), 112 at 320 and on the iPad column.
        #expect(DiscoverIssueLayout.railCover(column: 350, gutter: 20) == CGSize(width: 100, height: 150))
        #expect(DiscoverIssueLayout.railCover(column: 288, gutter: 16) == CGSize(width: 112, height: 168))
        #expect(DiscoverIssueLayout.railCover(column: 640, gutter: 20) == CGSize(width: 112, height: 168))
        #expect(DiscoverIssueLayout.railSpacing == 14)
        #expect(DiscoverIssueLayout.railCap == 10)
        #expect(DiscoverIssueLayout.offersSeeAll(total: 8, shown: 4))
        #expect(!DiscoverIssueLayout.offersSeeAll(total: 4, shown: 4))
    }
}

@Suite("Discover lane (DC): copy")
struct DCDiscoverCopyTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test("Opening row: the Berlin date without abbreviation stops; EN and DE")
    func opening() throws {
        // Tuesday 3 November 2026, 23:30 UTC on the 2nd is already the 3rd in Berlin.
        let now = try date("2026-11-02T23:30:00Z")
        #expect(DiscoverIssueCopy.openingKicker(now: now, german: false, timeZone: berlin) == "Today's issue · Tue 3 Nov")
        #expect(DiscoverIssueCopy.openingKicker(now: now, german: true, timeZone: berlin) == "Heutige Ausgabe · Di 3. Nov")
        #expect(DiscoverIssueCopy.issueDate(try date("2026-03-16T10:00:00Z"), german: true, timeZone: berlin) == "Mo 16. Mär")
        #expect(DiscoverIssueCopy.openingHeadline(german: false) == "Edited for you.")
        #expect(DiscoverIssueCopy.openingHeadline(german: true) == "Für dich zusammengestellt.")
    }

    @Test("The cover story's tab: the eyebrow split at its first space (shipped eyebrows)")
    func tab() {
        #expect(DiscoverIssueCopy.tabParts("Today's pick").small == "Today's")
        #expect(DiscoverIssueCopy.tabParts("Today's pick").large == "pick")
        #expect(DiscoverIssueCopy.tabParts("Tipp des Tages").small == "Tipp")
        #expect(DiscoverIssueCopy.tabParts("Tipp des Tages").large == "des Tages")
        #expect(DiscoverIssueCopy.tabParts(DiscoverIssueCopy.hiddenGem(german: true)).large == "Juwel")
        #expect(DiscoverIssueCopy.tabParts("Lesenswert").small == nil)
        #expect(DiscoverIssueCopy.tabParts("Lesenswert").large == "Lesenswert")
    }

    @Test("Facts: year · format · length, skipping what is missing; nil when nothing is known")
    func facts() {
        #expect(DiscoverIssueCopy.facts(kind: .anime, year: "2016", formatRaw: "MOVIE", episodes: 1, chapters: nil,
                                        length: false, german: false) == "2016 · Movie")
        #expect(DiscoverIssueCopy.facts(kind: .anime, year: "2016", formatRaw: "TV", episodes: 12, chapters: nil,
                                        length: true, german: false) == "2016 · TV · 12 eps")
        #expect(DiscoverIssueCopy.facts(kind: .anime, year: "2016", formatRaw: "TV", episodes: 12, chapters: nil,
                                        length: true, german: true) == "2016 · TV · 12 Folgen")
        #expect(DiscoverIssueCopy.facts(kind: .manga, year: "1998", formatRaw: "MANGA", episodes: nil, chapters: 327,
                                        length: true, german: false) == "1998 · Manga · 327 ch.")
        #expect(DiscoverIssueCopy.facts(kind: .manga, year: "1998", formatRaw: "MANGA", episodes: nil, chapters: 327,
                                        length: true, german: true) == "1998 · Manga · 327 Kap.")
        #expect(DiscoverIssueCopy.facts(kind: .anime, year: "TBA", formatRaw: nil, episodes: nil, chapters: nil,
                                        length: true, german: false) == nil)
        #expect(DiscoverIssueCopy.friendLine(2, german: false) == "2 in your clubs ›")
        #expect(DiscoverIssueCopy.friendLine(2, german: true) == "2 in deinen Clubs ›")
    }

    @Test("Glance: the next stated slot (24 h, Berlin), else the last one, else the titles; EN and DE")
    func glance() throws {
        let now = try date("2026-11-03T15:00:00Z")  // 16:00 Berlin
        let later = DiscoverAiringSlot(animeId: 1, airingAt: try date("2026-11-03T20:30:00Z"), episode: 7)
        let sooner = DiscoverAiringSlot(animeId: 2, airingAt: try date("2026-11-03T17:00:00Z"), episode: nil)
        let earlier = DiscoverAiringSlot(animeId: 3, airingAt: try date("2026-11-03T09:00:00Z"), episode: 4)
        let entries = [
            DiscoverIssueCopy.AiringEntry(title: "Mob Psycho 100", slot: later),
            DiscoverIssueCopy.AiringEntry(title: "Dandadan", slot: sooner),
            DiscoverIssueCopy.AiringEntry(title: "Frieren", slot: earlier),
            DiscoverIssueCopy.AiringEntry(title: "Mushishi", slot: nil)
        ]
        #expect(DiscoverIssueCopy.glanceCaption(entries, now: now, german: false, timeZone: berlin) == "Next: Dandadan\u{00A0}at\u{00A0}18:00")
        let withEpisode = [entries[0], entries[2]]
        #expect(DiscoverIssueCopy.glanceCaption(withEpisode, now: now, german: false, timeZone: berlin)
                == "Next: Mob Psycho 100 · Ep.\u{00A0}7\u{00A0}at\u{00A0}21:30")
        #expect(DiscoverIssueCopy.glanceCaption(withEpisode, now: now, german: true, timeZone: berlin)
                == "Als Nächstes: Mob Psycho 100 · Folge\u{00A0}7\u{00A0}um\u{00A0}21:30")
        let lateNight = try date("2026-11-03T22:00:00Z")
        #expect(DiscoverIssueCopy.glanceCaption(withEpisode, now: lateNight, german: false, timeZone: berlin)
                == "Last: Mob Psycho 100 · Ep.\u{00A0}7")
        #expect(DiscoverIssueCopy.glanceCaption(withEpisode, now: lateNight, german: true, timeZone: berlin)
                == "Zuletzt: Mob Psycho 100 · Folge\u{00A0}7")
        let untimed = [DiscoverIssueCopy.AiringEntry(title: "A", slot: nil), DiscoverIssueCopy.AiringEntry(title: "B", slot: nil),
                       DiscoverIssueCopy.AiringEntry(title: "C", slot: nil)]
        #expect(DiscoverIssueCopy.glanceCaption(untimed, now: now, german: false, timeZone: berlin) == "A · B")
        #expect(DiscoverIssueCopy.glanceCaption([], now: now, german: false, timeZone: berlin) == nil)
        #expect(DiscoverIssueCopy.clock(try date("2026-11-03T08:05:00Z"), timeZone: berlin) == "09:05")
        #expect(DiscoverIssueCopy.glanceTitle(german: false) == EditorialDiscoverRoute.animeAiringToday.title(german: false))
        #expect(DiscoverIssueCopy.glanceTitle(german: true) == EditorialDiscoverRoute.animeAiringToday.title(german: true))
    }

    @Test("Contents: at most five names, then +n (hidden + folded); omitted under two sections")
    func contents() {
        func entries(_ count: Int) -> [DiscoverContents.Entry] {
            (0..<count).map { DiscoverContents.Entry(id: "s\($0)", name: "Section \($0)", count: 8) }
        }
        #expect(DiscoverContents.line(page: entries(1), folded: 4) == nil)
        #expect(DiscoverContents.line(page: [], folded: 4) == nil)
        let full = DiscoverContents.line(page: entries(6), folded: 4)
        #expect(full?.names.count == 5)
        #expect(full?.more == 5)
        #expect(full?.moreTarget == "s5", "+n first scrolls to the first section not named")
        let folded = DiscoverContents.line(page: entries(3), folded: 2)
        #expect(folded?.names.count == 3)
        #expect(folded?.more == 2)
        #expect(folded?.moreTarget == DiscoverContents.foldAnchor)
        let complete = DiscoverContents.line(page: entries(2), folded: 0)
        #expect(complete?.more == nil)
        #expect(complete?.moreTarget == nil)
        #expect(DiscoverIssueCopy.contentsMore(4, german: false) == "+4 more")
        #expect(DiscoverIssueCopy.contentsMore(4, german: true) == "+4 weitere")
        #expect(DiscoverIssueCopy.contentsSpoken(name: "New to you", count: 8, german: false) == "New to you, 8 titles")
        #expect(DiscoverIssueCopy.browseTitle(german: true) == "Den Katalog durchstöbern")
        #expect(DiscoverIssueCopy.browseKicker(german: false) == "Everything")
    }

    @Test("Fold: its words, its trailing names and its session-memory key (F3)")
    func fold() {
        #expect(DiscoverIssueCopy.foldShow(4, german: false) == "Show 4 more sections")
        #expect(DiscoverIssueCopy.foldShow(4, german: true) == "4 weitere Bereiche zeigen")
        #expect(DiscoverIssueCopy.foldShow(1, german: false) == "Show 1 more section")
        #expect(DiscoverIssueCopy.foldFewer(german: false) == "Show fewer")
        #expect(DiscoverIssueCopy.foldFewer(german: true) == "Weniger zeigen")
        #expect(DiscoverIssueCopy.foldTrailing(names: ["Classics", "Top rated", "This season", "Just added"], expanded: false)
                == "Classics, Top rated +2 ⌄")
        #expect(DiscoverIssueCopy.foldTrailing(names: ["Classics"], expanded: false) == "Classics ⌄")
        #expect(DiscoverIssueCopy.foldTrailing(names: [], expanded: true) == "⌃")
        #expect(KuroFold.key(page: DiscoverIssueCopy.foldPage, section: DiscoverIssueCopy.foldSection) == "discover#more")
    }

    @Test("Fold memory is per run: a new memory starts folded, whatever the old device default says")
    @MainActor
    func foldMemory() throws {
        let suite = "kuro.tests.dc-fold.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "kuro_discover_show_more")
        let memory = KuroFoldMemory()
        let binding = memory.binding(page: DiscoverIssueCopy.foldPage, section: DiscoverIssueCopy.foldSection)
        #expect(binding.wrappedValue == false)
        binding.wrappedValue = true
        #expect(memory.isExpanded(page: "discover", section: "more"))
        #expect(KuroFoldMemory().isExpanded(page: "discover", section: "more") == false)
    }

    @Test("States, See all and the index: shipped words, the empty line names only what is on screen")
    func statesAndActions() {
        #expect(DiscoverIssueCopy.emptyTitle(german: false) == "Nothing to show yet.")
        #expect(DiscoverIssueCopy.emptyTitle(german: true) == "Noch nichts zu zeigen.")
        #expect(DiscoverIssueCopy.emptyMessage(browseOffered: true, german: false) == "Pull to refresh, or browse the catalogue.")
        #expect(DiscoverIssueCopy.emptyMessage(browseOffered: false, german: false) == "Pull to refresh.")
        #expect(DiscoverIssueCopy.emptyMessage(browseOffered: false, german: true) == "Zum Aktualisieren ziehen.")
        #expect(DiscoverIssueCopy.offlineLead(german: false) == "You're offline.")
        #expect(DiscoverIssueCopy.offlineRest(german: true) == "Du siehst die zuletzt geladene Ausgabe.")
        #expect(DiscoverIssueCopy.retry(german: false) == "Try again")
        #expect(DiscoverIssueCopy.seeAll(8, german: false) == "See all 8 ›")
        #expect(DiscoverIssueCopy.seeAll(8, german: true) == "Alle 8 ansehen ›")
        // The UI tests find the action by its label's start.
        #expect(DiscoverIssueCopy.seeAllSpoken(8, section: "New to you.", german: false).hasPrefix("See all"))
        #expect(DiscoverIssueCopy.indexNumber(1) == "01")
        #expect(DiscoverIssueCopy.indexSpoken(1, german: false) == "Number 1 in our order")
        #expect(DiscoverIssueCopy.indexSpoken(1, german: true) == "Nummer 1 in unserer Reihenfolge")
        #expect(DiscoverIssueCopy.refineLabel(german: true) == "Diese Leiste eingrenzen")
        #expect(DiscoverIssueCopy.onYourList(german: true) == "Auf deiner Liste")
        #expect(DiscoverIssueCopy.heading("New to you") == "New to you.")
        #expect(DiscoverIssueCopy.heading("Trending.") == "Trending.")
    }

    @Test("VoiceOver: the cover story is one sentence; a feature reads its title and facts")
    func spoken() {
        #expect(DiscoverIssueCopy.storySpoken(eyebrow: "Today's pick", title: "Mushishi",
                                              argument: "Quiet, strange and kind", facts: "2005 · TV")
                == "Today's pick: Mushishi. Quiet, strange and kind. 2005, TV.")
        #expect(DiscoverIssueCopy.storySpoken(eyebrow: "Hidden gem", title: "Cowboy Bebop", argument: nil, facts: nil)
                == "Hidden gem: Cowboy Bebop.")
        #expect(DiscoverIssueCopy.featureSpoken(title: "Mob Psycho 100", facts: "2016 · TV · 12 eps")
                == "Mob Psycho 100. 2016, TV, 12 eps.")
    }
}

@Suite("Discover lane (DC): page")
@MainActor
struct DCDiscoverPageTests {
    @Test("Discover follows its issue (All and Anime warm, Manga the manga canvas); Clubs is warm")
    func canvas() {
        #expect(KuroMainView.Section.discover.canvas(mangaHome: false) == Color.kuroCanvasHome)
        #expect(KuroMainView.Section.discover.canvas(mangaHome: true) == Color.kuroCanvasHome,
                "Home's medium never colours Discover")
        #expect(KuroMainView.Section.discover.canvas(mangaHome: false, mangaDiscover: true) == Color.kuroCanvasHomeManga)
        #expect(KuroMainView.Section.clubs.canvas(mangaHome: true) == Color.kuroCanvasHome)
        #expect(KuroMainView.Section.home.canvas(mangaHome: false, mangaDiscover: true) == Color.kuroCanvasHome)
        #expect(KuroMainView.Section.collection.canvas(mangaHome: false) == Color.kuroBackground, "Collection stays white (D16)")
    }

    @Test("The daily feature as a cover story: its own media, banner and plain argument; manga keeps manga")
    func story() throws {
        let json = #"{"media_type":"MANGA","media_id":504,"title":"Vagabond","cover_image_large":"https://x.invalid/c.jpg","banner_image":null,"genres":["Seinen"],"score":92,"year":1998,"format":"MANGA","argument":"Every stroke has weight.<br>"}"#
        let feature = try JSONDecoder().decode(DailyFeature.self, from: Data(json.utf8))
        let story = DiscoverStory(feature: feature, eyebrow: "Today's pick")
        #expect(story.key == MediaKey(kind: .manga, id: 504))
        #expect(story.bannerRaw == nil, "no banner: the capped spread")
        #expect(story.artRaw == "https://x.invalid/c.jpg")
        #expect(story.argument == "Every stroke has weight.")
        #expect(story.facts(length: false, german: false) == "1998 · Manga")
    }
}

@Suite("Discover lane (DC): sections and Plan key")
@MainActor
struct DCDiscoverSectionTests {
    typealias Sections = DiscoverIssueSections

    /// Every rail holds content; the Hidden gem is anime.
    private func full(_ issue: Sections.Issue, realm: Bool, becauseYou: Bool = false) -> Sections.Inputs {
        Sections.Inputs(issue: issue, realmRails: realm, newToYou: true, becauseYou: becauseYou, tonightShelf: true,
                        essentials: true, hiddenGemKind: .anime, mangaNewToYou: true, trending: true, essentialsManga: true,
                        classics: true, currentSeason: true, topRated: true, newlyAdded: true, classicsManga: true,
                        trendingManga: true, topRatedManga: true, newlyAddedManga: true)
    }

    @Test("All: the curated order; Because-You replaces New to you; realm rails only behind their flag; Essential manga folded")
    func allIssue() {
        // Details-songs spec §14.2 (D17): on All, Manga new to you is one rail and Essential manga is the
        // fold's first section.
        #expect(Sections.main(full(.all, realm: false)) == [.newToYou, .essentials, .mangaNewToYou, .trending])
        #expect(Sections.main(full(.all, realm: false, becauseYou: true))
                == [.becauseYou, .essentials, .mangaNewToYou, .trending])
        #expect(Sections.main(full(.all, realm: true))
                == [.newToYou, .tonightShelf, .essentials, .hiddenGem, .mangaNewToYou, .trending])
        #expect(Sections.fold(full(.all, realm: false)) == [.mangaEssentials,
                                                            .animeClassics, .animeCurrentSeason, .animeTopRated, .animeNewlyAdded,
                                                            .mangaClassics, .mangaTrending, .mangaTopRated, .mangaNewlyAdded])
        #expect(Sections.drawsMangaNewToYouAsRail(.all))
        #expect(!Sections.drawsMangaNewToYouAsRail(.manga))
    }

    @Test("Anime: no manga sections, Because-You never replaces New to you; the gem must match the issue")
    func animeIssue() {
        #expect(Sections.main(full(.anime, realm: false, becauseYou: true)) == [.newToYou, .essentials, .trending])
        #expect(Sections.main(full(.anime, realm: true)) == [.newToYou, .tonightShelf, .essentials, .hiddenGem, .trending])
        var mangaGem = full(.anime, realm: true)
        mangaGem.hiddenGemKind = .manga
        #expect(!Sections.main(mangaGem).contains(.hiddenGem))
        #expect(Sections.fold(full(.anime, realm: true)) == [.animeClassics, .animeCurrentSeason, .animeTopRated, .animeNewlyAdded])
    }

    @Test("Manga: Manga new to you leads; no anime sections and no realm rails for an anime gem")
    func mangaIssue() {
        #expect(Sections.main(full(.manga, realm: true, becauseYou: true)) == [.mangaNewToYou, .essentialsManga])
        var mangaGem = full(.manga, realm: true)
        mangaGem.hiddenGemKind = .manga
        #expect(Sections.main(mangaGem) == [.mangaNewToYou, .hiddenGem, .essentialsManga])
        #expect(Sections.fold(full(.manga, realm: false)) == [.mangaClassics, .mangaTrending, .mangaTopRated, .mangaNewlyAdded])
    }

    @Test("Empty rails are skipped, whatever the issue")
    func emptyRails() {
        let none = Sections.Inputs(issue: .all, realmRails: true)
        #expect(Sections.main(none).isEmpty)
        #expect(Sections.fold(none).isEmpty)
    }

    @Test("Lead: today's pick when it matches, the skeleton while it resolves (never on Manga), then the fallbacks")
    func lead() {
        #expect(Sections.lead(issue: .all, dailyFeatureKind: .manga, dailyFeatureResolved: true, hasFeatured: true,
                              hasEssentialsManga: true, hasTrendingManga: true) == .dailyFeature)
        #expect(Sections.lead(issue: .anime, dailyFeatureKind: .manga, dailyFeatureResolved: true, hasFeatured: true,
                              hasEssentialsManga: true, hasTrendingManga: true) == .season)
        #expect(Sections.lead(issue: .all, dailyFeatureKind: nil, dailyFeatureResolved: false, hasFeatured: true,
                              hasEssentialsManga: true, hasTrendingManga: true) == .skeleton)
        #expect(Sections.lead(issue: .manga, dailyFeatureKind: nil, dailyFeatureResolved: false, hasFeatured: true,
                              hasEssentialsManga: false, hasTrendingManga: true) == .manga)
        #expect(Sections.lead(issue: .manga, dailyFeatureKind: .anime, dailyFeatureResolved: true, hasFeatured: true,
                              hasEssentialsManga: false, hasTrendingManga: false) == .none)
        #expect(Sections.lead(issue: .anime, dailyFeatureKind: nil, dailyFeatureResolved: true, hasFeatured: false,
                              hasEssentialsManga: true, hasTrendingManga: true) == .none)
    }

    @Test("The Plan key honours the pager's tap suppression (a swipe that starts on it never plans)")
    func planKeyGate() {
        #expect(TastePlanKey.acceptsTap(suppressCardTaps: false))
        #expect(!TastePlanKey.acceptsTap(suppressCardTaps: true))
    }
}
