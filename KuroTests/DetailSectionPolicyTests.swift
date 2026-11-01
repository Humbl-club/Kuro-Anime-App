//
//  DetailSectionPolicyTests.swift
//  KuroTests
//
//  The one detail page's pure rules (prototype fidelity, Task 6): sections shown only with real data,
//  untracked titles without progress, ladder season numbering and the status mark's actions.
//

import Testing
import KuroCore
import KuroLibrary
@testable import Kuro

@MainActor
@Suite("Detail section policy")
struct DetailSectionPolicyTests {
    @Test("A sparse title shows only its real sections: no seasons, songs, characters or club")
    func sparseTitleShowsOnlyRealSections() {
        let withCredits = DetailInput(hasSynopsis: true, creditCount: 2)
        #expect(DetailSectionPolicy.sections(for: withCredits) == [.hero, .story, .credits])
        let bare = DetailInput(hasSynopsis: true)
        #expect(DetailSectionPolicy.sections(for: bare) == [.hero, .story])
        // One ladder entry is not a series: no "Seasons" heading.
        let single = DetailInput(hasSynopsis: true, seasonCount: 1)
        #expect(!DetailSectionPolicy.sections(for: single).contains(.seasons))
    }

    @Test("An untracked title has no progress and no Up next; the mark reads Not in your list")
    func untrackedHidesProgress() {
        let untracked = DetailInput(hasSynopsis: true, isTracked: false, unitCount: 3, hasNextUnit: true)
        let sections = DetailSectionPolicy.sections(for: untracked)
        #expect(!sections.contains(.progress))
        #expect(sections.contains(.units))
        #expect(!DetailSectionPolicy.showsUpNext(for: untracked))
        #expect(DetailStatusCopy.label(status: nil, kind: .anime, german: false) == "Not in your list")
        #expect(DetailStatusCopy.label(status: nil, kind: .anime, german: true) == "Nicht in deiner Liste")

        // Untracked with no unit rows: no units section at all (an Up next alone never shows).
        let noRows = DetailInput(hasSynopsis: true, isTracked: false, unitCount: 0, hasNextUnit: true)
        #expect(!DetailSectionPolicy.sections(for: noRows).contains(.units))

        let tracked = DetailInput(hasSynopsis: true, isTracked: true, unitCount: 0, hasNextUnit: true)
        #expect(DetailSectionPolicy.sections(for: tracked).contains(.progress))
        #expect(DetailSectionPolicy.sections(for: tracked).contains(.units))
        #expect(DetailSectionPolicy.showsUpNext(for: tracked))
        #expect(DetailStatusCopy.label(status: .current, kind: .anime, german: false) == "Watching")
        #expect(DetailStatusCopy.label(status: .current, kind: .manga, german: false) == "Reading")
    }

    @Test("Ladder numbering: TV S1 → TV S2 → MOVIE → TV S3 numbers 1, 2, 3 and keeps the film as an extra")
    func ladderNumbering() {
        let chain = [
            LadderChainEntry(mediaId: 1, title: "Story", format: "TV", year: 2020),
            LadderChainEntry(mediaId: 2, title: "Story Season 2", format: "TV", year: 2021),
            LadderChainEntry(mediaId: 3, title: "Story the Movie", format: "MOVIE", year: 2022),
            LadderChainEntry(mediaId: 4, title: "Story Season 3", format: "TV", year: 2023)
        ]
        let result = LadderSeasons.seasons(chain: chain, current: 2)
        #expect(result.numbered.map(\.number) == [1, 2, 3])
        #expect(result.numbered.map(\.entry.mediaId) == [1, 2, 4])
        #expect(result.extras.map(\.entry.format) == ["MOVIE"])
        #expect(result.numbered.first(where: \.isCurrent)?.number == 2)
        #expect(LadderSeasons.currentNumber(result.numbered) == 2)

        // The same chain from one ladder answer (prequels, the open title, sequels).
        let ladder = Self.ladder(prequels: [Self.item(1, "Story", "TV", 2020)],
                                 sequels: [Self.item(3, "Story the Movie", "MOVIE", 2022),
                                           Self.item(4, "Story Season 3", "TV", 2023)])
        let fromLadder = LadderSeasons.seasons(from: ladder, current: chain[1])
        #expect(fromLadder.numbered.map(\.number) == [1, 2, 3])
        #expect(fromLadder.extras.count == 1)
    }

    @Test("Split-cour parts keep their own label and take no new season number")
    func splitCourParts() {
        let chain = [
            LadderChainEntry(mediaId: 1, title: "Titan Final Season", format: "TV"),
            LadderChainEntry(mediaId: 2, title: "Titan Final Season Part 2", format: "TV")
        ]
        let result = LadderSeasons.seasons(chain: chain, current: 2)
        #expect(result.numbered.map(\.number) == [1, nil])
        #expect(result.numbered.last?.partLabel == "Part 2")
        // One numbered season: the page never shows "Season 1" for it.
        #expect(LadderSeasons.currentNumber(result.numbered) == nil)
    }

    @Test("A single entry hides the seasons section and never invents Season 1")
    func singleEntryHidesSeasons() {
        let result = LadderSeasons.seasons(chain: [LadderChainEntry(mediaId: 9, title: "Mushishi", format: "TV")], current: 9)
        #expect(result.numbered.count + result.extras.count == 1)
        #expect(LadderSeasons.currentNumber(result.numbered) == nil)
        let input = DetailInput(hasSynopsis: true, seasonCount: result.numbered.count + result.extras.count)
        #expect(!DetailSectionPolicy.sections(for: input).contains(.seasons))
    }

    @Test("The status mark keeps List settings, Favourite, Verdict and Where to watch")
    func statusMarkKeepsActions() {
        for tracked in [false, true] {
            let actions = DetailStatusCopy.actions(isTracked: tracked)
            for required in [DetailStatusAction.listSettings, .favourite, .verdict, .providers] {
                #expect(actions.contains(required))
            }
            #expect(actions.first == .listSettings)
        }
        #expect(DetailStatusCopy.actionTitle(.providers, isTracked: true, kind: .anime, german: false) == "Where to watch")
        #expect(DetailStatusCopy.actionTitle(.listSettings, isTracked: true, kind: .anime, german: false) == "List settings")
        #expect(DetailStatusCopy.actionTitle(.listSettings, isTracked: false, kind: .anime, german: true) == "Zur Liste hinzufügen")
    }

    @Test("Up next stops at a known total; an unknown total keeps going")
    func nextUnit() {
        #expect(DetailSectionPolicy.nextUnit(progress: 6, total: 9) == 7)
        #expect(DetailSectionPolicy.nextUnit(progress: 9, total: 9) == nil)
        #expect(DetailSectionPolicy.nextUnit(progress: 0, total: nil) == 1)
        #expect(DetailSectionPolicy.nextUnit(progress: 40, total: nil) == 41)
    }

    @Test("Chain walk steps to the nearest season-format neighbour")
    func chainStep() {
        let prequels = [Self.item(1, "S1", "TV", 2018), Self.item(5, "Film", "MOVIE", 2019), Self.item(2, "S2", "TV", 2019)]
        #expect(LadderSeasons.step(prequels, excluding: [], towardsOlder: true)?.mediaId == 2)
        #expect(LadderSeasons.step(prequels, excluding: [2], towardsOlder: true)?.mediaId == 1)
        #expect(LadderSeasons.step([Self.item(5, "Film", "MOVIE", 2019)], excluding: [], towardsOlder: false)?.mediaId == 5)
        let manga = [MediaLadderItem(mediaType: "MANGA", mediaId: 7, title: "Book", coverImage: nil, year: 2010,
                                     format: "MANGA", rating: nil, reasonLabel: nil, sourceAuthorName: nil)]
        #expect(LadderSeasons.step(manga, excluding: [], towardsOlder: true) == nil)
    }

    @Test("Page copy in English and German")
    func copy() {
        #expect(DetailPageCopy.clubPeople(3, german: false) == "3 people in your clubs")
        #expect(DetailPageCopy.clubPeople(3, german: true) == "3 Personen aus deinen Clubs")
        #expect(DetailPageCopy.progressLabel(season: 2, german: false) == "Season 2 progress")
        #expect(DetailPageCopy.progressLabel(season: nil, german: true) == "Dein Fortschritt")
        #expect(DetailPageCopy.progressCaption(total: nil, releasing: true, german: false) == "Ongoing · total unknown")
        #expect(DetailPageCopy.progressCaption(total: nil, releasing: false, german: false) == nil)
        #expect(DetailPageCopy.aboutTitle(isSeason: true, german: false) == "About this season")
        #expect(DetailPageCopy.aboutTitle(isSeason: false, german: true) == "Über diese Geschichte")
    }

    // MARK: Fixtures

    private static func item(_ id: Int, _ title: String, _ format: String, _ year: Int) -> MediaLadderItem {
        MediaLadderItem(mediaType: "ANIME", mediaId: id, title: title, coverImage: nil, year: year, format: format,
                        rating: nil, reasonLabel: nil, sourceAuthorName: nil)
    }

    private static func ladder(prequels: [MediaLadderItem], sequels: [MediaLadderItem]) -> MediaLadderResponse {
        MediaLadderResponse(sourceMaterial: [], adaptations: [], prequels: prequels, sequels: sequels, sideStories: [],
                            spinOffs: [], entryPoint: nil, nextStep: nil, primarySource: nil, primaryAdaptation: nil,
                            franchiseNote: nil, coverageStatus: nil, totalFranchiseCount: nil,
                            alternateAdaptationSummary: nil)
    }
}
