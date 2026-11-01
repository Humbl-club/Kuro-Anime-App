//
//  MangaDetailLaneTests.swift
//  KuroTests
//
//  The manga detail's pure rules (prototype fidelity, Task 7): placeholder chapters are hidden, the
//  bookmark states a total only when one is known, "Seen the anime?" needs an anime adaptation in the
//  ladder, "Read with the publisher" needs a real reading link, and the status mark keeps every action.
//

import Foundation
import Testing
import KuroCore
import KuroLibrary
@testable import Kuro

@MainActor
@Suite("Manga detail lane")
struct MangaDetailLaneTests {
    private static func chapter(_ number: Int, title: String?, date: Date? = nil) -> MangaChapter {
        MangaChapter(id: number, mangaId: 1, number: number, title: title, titleRomaji: nil, description: nil,
                     releaseDate: date, releaseAt: nil, thumbnail: nil, pages: nil,
                     createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    private static func item(_ type: String, _ id: Int, format: String) -> MediaLadderItem {
        MediaLadderItem(mediaType: type, mediaId: id, title: "Title \(id)", coverImage: nil, year: 2022, format: format,
                        rating: nil, reasonLabel: nil, sourceAuthorName: nil)
    }

    private static func ladder(primary: MediaLadderItem? = nil, adaptations: [MediaLadderItem] = []) -> MediaLadderResponse {
        MediaLadderResponse(sourceMaterial: [], adaptations: adaptations, prequels: [], sequels: [], sideStories: [],
                            spinOffs: [], entryPoint: nil, nextStep: nil, primarySource: nil, primaryAdaptation: primary,
                            franchiseNote: nil, coverageStatus: nil, totalFranchiseCount: nil, alternateAdaptationSummary: nil)
    }

    private static func link(_ url: String, title: String = "MANGA Plus") -> ProviderSheetItem {
        ProviderSheetItem(id: url, title: title, url: url, subtitle: nil, isVerified: false)
    }

    @Test("Placeholder chapters hide the chapter list; Up next stays")
    func placeholderChaptersHideTheChapterList() {
        let placeholders = [Self.chapter(24, title: "Chapter 24"), Self.chapter(25, title: "chapter 25"),
                            Self.chapter(26, title: nil), Self.chapter(27, title: "  ")]
        #expect(!MangaDetailSections.chaptersAreReal(placeholders))
        #expect(!MangaDetailSections.chaptersAreReal([]))
        // A real title, or a release date, makes the list real.
        #expect(MangaDetailSections.chaptersAreReal(placeholders + [Self.chapter(28, title: "The Devil's Bargain")]))
        #expect(MangaDetailSections.chaptersAreReal([Self.chapter(28, title: "Chapter 28", date: Date(timeIntervalSince1970: 1_700_000_000))]))
        // A title that only repeats the number is never shown as the chapter's own title.
        #expect(MangaDetailSections.realTitle(Self.chapter(28, title: "Chapter 28", date: Date())) == nil)
        #expect(MangaDetailSections.realTitle(Self.chapter(28, title: "The Devil's Bargain")) == "The Devil's Bargain")

        // Tracked, placeholders only: no rows counted, but the section still exists for Up next.
        let input = MangaDetailSections.input(hasSynopsis: true, hasHook: false, clubPeople: 0, isTracked: true,
                                              chapters: placeholders, nextChapter: 25, hasAdaptation: false,
                                              characterCount: 0, creditRows: 0, hasPublisherLink: false, hasClubs: false)
        #expect(input.unitCount == 0)
        #expect(DetailSectionPolicy.sections(for: input).contains(.units))
        #expect(DetailSectionPolicy.showsUpNext(for: input))
        // Untracked with placeholders: no chapters block at all.
        var untracked = input
        untracked.isTracked = false
        #expect(!DetailSectionPolicy.sections(for: untracked).contains(.units))
        #expect(!DetailSectionPolicy.sections(for: untracked).contains(.progress))
    }

    @Test("The bookmark shows Ch. N / total only when the total is known")
    func bookmarkTotalOnlyWhenKnown() {
        #expect(MangaDetailSections.bookmarkTotal(chapterCount: 25) == 25)
        #expect(MangaDetailSections.bookmarkTotal(chapterCount: nil) == nil)
        #expect(MangaDetailSections.bookmarkTotal(chapterCount: 0) == nil)
        #expect(MangaDetailSections.bookmarkSpoken(progress: 24, total: 25, german: false) == "Chapter 24 of 25")
        #expect(MangaDetailSections.bookmarkSpoken(progress: 24, total: nil, german: false) == "Chapter 24")
        #expect(MangaDetailSections.bookmarkSpoken(progress: 24, total: 25, german: true) == "Kapitel 24 von 25")
        #expect(MangaDetailSections.bookmarkCaption(total: 25, releasing: false, german: false) == "25 chapters")
        #expect(MangaDetailSections.bookmarkCaption(total: 25, releasing: false, german: true) == "25 Kapitel")
        #expect(MangaDetailSections.bookmarkCaption(total: nil, releasing: true, german: false) == "Ongoing · total unknown")
        #expect(MangaDetailSections.bookmarkCaption(total: nil, releasing: false, german: false) == nil)
        // No preview wording ships.
        #expect(MangaDetailSections.bookmarkCaption(total: 25, releasing: false, german: false)?.contains("preview") == false)
    }

    @Test("Up next: a known total caps it; an unknown total offers the next chapter, as Home does")
    func nextChapterCeiling() {
        #expect(MangaDetailSections.nextChapter(progress: 24, chapterCount: 25) == 25)
        #expect(MangaDetailSections.nextChapter(progress: 25, chapterCount: 25) == nil)
        #expect(MangaDetailSections.nextChapter(progress: 24, chapterCount: nil) == 25)
        #expect(MangaDetailSections.nextChapter(progress: 0, chapterCount: nil) == 1)
        // A manga not yet released offers no chapter, even with a known count.
        #expect(MangaDetailSections.nextChapter(progress: 0, chapterCount: 25, status: "NOT_YET_RELEASED") == nil)
        #expect(MangaDetailSections.nextChapter(progress: 0, chapterCount: nil, status: "not_yet_released") == nil)
        // Releasing: the schedule's next chapter is not offered (1197 is upcoming, 1196 is out).
        #expect(MangaDetailSections.nextChapter(progress: 1195, chapterCount: nil, status: "RELEASING", scheduledNext: 1197) == 1196)
        #expect(MangaDetailSections.nextChapter(progress: 1196, chapterCount: nil, status: "RELEASING", scheduledNext: 1197) == nil)
        // Releasing with no schedule: as Home's leaf key.
        #expect(MangaDetailSections.nextChapter(progress: 1196, chapterCount: nil, status: "RELEASING") == 1197)
    }

    @Test("Official anime site: only AniList's Official Site with a safe URL")
    func officialAnimeSite() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func link(_ site: String?, _ url: String, disabled: Bool = false) -> ExternalLink {
            ExternalLink(id: Int.random(in: 1...9999), mediaType: "ANIME", mediaId: 1, site: site, url: url, language: nil,
                         color: nil, priority: nil, isDisabled: disabled, createdAt: date, updatedAt: date)
        }
        #expect(MangaDetailSections.officialSite(in: []) == nil)
        #expect(MangaDetailSections.officialSite(in: [link("Crunchyroll", "https://crunchyroll.com/x")]) == nil)
        #expect(MangaDetailSections.officialSite(in: [link("Official Site", "javascript:alert(1)")]) == nil)
        #expect(MangaDetailSections.officialSite(in: [link("Official Site", "https://jujutsukaisen.jp", disabled: true)]) == nil)
        #expect(MangaDetailSections.officialSite(in: [link("Official Site", "https://jujutsukaisen.jp")])?.host == "jujutsukaisen.jp")
    }

    @Test("Seen the anime? appears only with an anime adaptation in the ladder")
    func seenTheAnimeNeedsAnAnimeAdaptation() {
        #expect(MangaDetailSections.animeAdaptation(in: .empty) == nil)
        // A novel or a second manga is not an anime adaptation.
        let notAnime = Self.ladder(primary: Self.item("MANGA", 9, format: "NOVEL"), adaptations: [Self.item("MANGA", 9, format: "NOVEL")])
        #expect(MangaDetailSections.animeAdaptation(in: notAnime) == nil)
        let anime = Self.ladder(adaptations: [Self.item("MANGA", 9, format: "NOVEL"), Self.item("ANIME", 127230, format: "TV")])
        #expect(MangaDetailSections.animeAdaptation(in: anime)?.mediaId == 127230)
        let primary = Self.ladder(primary: Self.item("ANIME", 5, format: "TV"), adaptations: [Self.item("ANIME", 6, format: "MOVIE")])
        #expect(MangaDetailSections.animeAdaptation(in: primary)?.mediaId == 5)

        let without = MangaDetailSections.input(hasSynopsis: true, hasHook: false, clubPeople: 0, isTracked: false, chapters: [],
                                                nextChapter: 1, hasAdaptation: false, characterCount: 0, creditRows: 0,
                                                hasPublisherLink: false, hasClubs: false)
        #expect(!DetailSectionPolicy.sections(for: without).contains(.source))
        var with = without
        with.hasSource = true
        #expect(DetailSectionPolicy.sections(for: with).contains(.source))
    }

    @Test("Read legally appears only with a legal read link (never labelled as the publisher)")
    func publisherRowNeedsALink() {
        #expect(MangaDetailSections.publisherLink(from: []) == nil)
        #expect(MangaDetailSections.publisherLink(from: [Self.link("javascript:alert(1)")]) == nil)
        let link = Self.link("https://mangaplus.shueisha.co.jp/titles/100037")
        #expect(MangaDetailSections.publisherLink(from: [Self.link("file:///etc/hosts"), link]) == link)
        #expect(MangaDetailSections.publisherCaption(link, count: 1, german: false) == "MANGA Plus")
        #expect(MangaDetailSections.publisherCaption(link, count: 3, german: false) == "MANGA Plus and 2 more")

        // With credits_cast_v1 off there are no author rows: the publisher row alone keeps
        // "Behind the pages." on the page; with neither, the section is hidden.
        let noCredits = MangaDetailSections.input(hasSynopsis: true, hasHook: false, clubPeople: 0, isTracked: false, chapters: [],
                                                  nextChapter: 1, hasAdaptation: false, characterCount: 0, creditRows: 0,
                                                  hasPublisherLink: true, hasClubs: false)
        #expect(DetailSectionPolicy.sections(for: noCredits) == [.hero, .story, .credits])
        var bare = noCredits
        bare.creditCount = 0
        #expect(DetailSectionPolicy.sections(for: bare) == [.hero, .story])
    }

    @Test("Behind the pages names only credited authors; nothing is invented")
    func mangaCredits() {
        let fujimoto = Author(id: 1, anilistId: nil, nameFull: "Tatsuki Fujimoto", nameNative: nil, imageLarge: nil, description: nil)
        let unnamed = Author(id: 2, anilistId: nil, nameFull: nil, nameNative: nil, imageLarge: nil, description: nil)
        let rows = DetailCreditRow.manga(authors: [(fujimoto, "Story & Art"), (unnamed, "Art"), (fujimoto, "Story & Art")], german: false)
        #expect(rows.map(\.role) == ["Story & art"])
        #expect(rows.map(\.name) == ["Tatsuki Fujimoto"])
        let split = DetailCreditRow.manga(authors: [(fujimoto, "Story"), (unnamed, "Art")], german: true)
        #expect(split.map(\.role) == ["Story"])
        #expect(DetailCreditRow.manga(authors: [], german: false).isEmpty)
    }

    @Test("The manga status mark keeps List settings, Favourite, Verdict, Where to read, club and share")
    func statusMarkKeepsEveryAction() {
        let actions = DetailStatusCopy.actions(isTracked: true)
        #expect(actions == [.listSettings, .favourite, .verdict, .providers, .addToClub, .share])
        #expect(DetailStatusCopy.actionTitle(.providers, isTracked: true, kind: .manga, german: false) == "Where to read")
        #expect(DetailStatusCopy.label(status: .current, kind: .manga, german: false) == "Reading")
        #expect(DetailStatusCopy.label(status: nil, kind: .manga, german: true) == "Nicht in deiner Liste")
        #expect(MangaDetailCopy.bookmark(german: false) == "Your bookmark")
        #expect(MangaDetailCopy.seriesOverview(german: true) == "Serienüberblick")
    }
}
