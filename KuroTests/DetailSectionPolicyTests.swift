//
//  DetailSectionPolicyTests.swift
//  KuroTests
//
//  The one detail page's pure rules (prototype fidelity, Task 6): sections shown only with real data,
//  untracked titles without progress, ladder season numbering and the status mark's actions.
//

import Foundation
import Testing
import KuroCore
import KuroLibrary
@testable import Kuro

@MainActor
@Suite("Detail section policy")
struct DetailSectionPolicyTests {
    @Test("Between us: the heading shows no member names while social activity is switched off")
    func betweenUsHonoursTheKillSwitch() {
        let roster = ["Mina", "Jules"].enumerated().map { index, name in
            SocialActivityStore.FriendTitleActivity(user_id: "u\(index)", display_name: name, status: "CURRENT",
                                                    progress: 3, rating: nil, updated_at: nil)
        }
        #expect(DetailBetweenUs.headingNames(roster, socialEnabled: true) == ["Mina", "Jules"])
        #expect(DetailBetweenUs.headingNames(roster, socialEnabled: false).isEmpty)
    }

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

    @Test("An airing title never offers an episode that has not aired")
    func airingCeiling() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let aired = DetailSectionPolicy.airedThrough(status: "RELEASING", nextEpisode: 6,
                                                     nextAiringAt: now.addingTimeInterval(3_600), now: now)
        #expect(aired == 5)
        #expect(DetailSectionPolicy.nextUnit(progress: 5, total: nil, airedThrough: aired) == nil)
        #expect(DetailSectionPolicy.nextUnit(progress: 4, total: nil, airedThrough: aired) == 5)
        // A stale row whose airing time has passed: episode 6 has aired, 7 has not (a ceiling, not none).
        #expect(DetailSectionPolicy.airedThrough(status: "RELEASING", nextEpisode: 6,
                                                 nextAiringAt: now.addingTimeInterval(-60), now: now) == 6)
        // A next episode with no time is treated as not yet aired.
        #expect(DetailSectionPolicy.airedThrough(status: "RELEASING", nextEpisode: 6, nextAiringAt: nil, now: now) == 5)
        // The release schedule wins over the catalogue row (here: a stale row says 6, the schedule 9).
        #expect(DetailSectionPolicy.airedThrough(status: "RELEASING", nextEpisode: 6,
                                                 nextAiringAt: now.addingTimeInterval(-60), scheduledNext: 9, now: now) == 8)
        // A finished show is capped by its total only.
        #expect(DetailSectionPolicy.airedThrough(status: "FINISHED", nextEpisode: 6,
                                                 nextAiringAt: now.addingTimeInterval(3_600), now: now) == nil)
    }

    @Test("A title not yet released offers no Up next, even with a known episode count")
    func notYetReleasedHasNoNextUnit() {
        let aired = DetailSectionPolicy.airedThrough(status: "NOT_YET_RELEASED", nextEpisode: nil, nextAiringAt: nil)
        #expect(aired == 0)
        #expect(DetailSectionPolicy.nextUnit(progress: 0, total: 12, airedThrough: aired) == nil)
        let input = DetailInput(hasSynopsis: true, isTracked: true, unitCount: 0, hasNextUnit: false)
        #expect(!DetailSectionPolicy.showsUpNext(for: input))
    }

    @Test("The schedule's next unit of the right kind sets the ceiling")
    func scheduledNextUnit() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = [
            ReleaseScheduleItem(medium: .anime, mediaId: 1, title: "T", unitKind: .season, unitNumber: 2,
                                releaseAt: at, basis: .confirmed, source: "anilist", precision: .instant),
            ReleaseScheduleItem(medium: .anime, mediaId: 1, title: "T", unitKind: .episode, unitNumber: 9,
                                releaseAt: at, basis: .confirmed, source: "anilist", precision: .instant)
        ]
        #expect(DetailSectionPolicy.scheduledNext(rows, kind: .episode) == 9)
        #expect(DetailSectionPolicy.scheduledNext(rows, kind: .chapter) == nil)
        #expect(DetailSectionPolicy.scheduledNext([], kind: .episode) == nil)
    }

    @Test("social_activity_v1 off hides Between us notes and the club presence row")
    func socialKillSwitch() {
        let flagOff = DetailInput(hasSynopsis: true, clubPeopleCount: 3, hasClubs: true, socialEnabled: false)
        let sections = DetailSectionPolicy.sections(for: flagOff)
        #expect(!sections.contains(.betweenUs))
        #expect(!sections.contains(.clubPresence))
        // Fail-closed default: an input that never says the flag is on shows neither.
        #expect(!DetailSectionPolicy.sections(for: DetailInput(clubPeopleCount: 2, hasClubs: true)).contains(.betweenUs))
        let flagOn = DetailInput(hasSynopsis: true, clubPeopleCount: 3, hasClubs: true, socialEnabled: true)
        #expect(DetailSectionPolicy.sections(for: flagOn).contains(.betweenUs))
        #expect(DetailSectionPolicy.sections(for: flagOn).contains(.clubPresence))
        // Club rails holding the title keep the card (the legacy club section ignored the social flag).
        let railsOnly = DetailInput(hasSynopsis: true, clubPeopleCount: 3, hasClubs: true, socialEnabled: false, clubRailCount: 1)
        #expect(DetailSectionPolicy.sections(for: railsOnly).contains(.betweenUs))
        #expect(!DetailSectionPolicy.sections(for: railsOnly).contains(.clubPresence))
        // No clubs: nothing, whatever the flag.
        #expect(!DetailSectionPolicy.sections(for: DetailInput(hasClubs: false, socialEnabled: true, clubRailCount: 1)).contains(.betweenUs))
    }

    @Test("Chain walk: a confirmed walk to the first season is proven")
    func chainWalkProven() async {
        // S1 (1) ← S2 (2) ← S3 (3, open). Each prequel's ladder lists its child among its sequels.
        let ladders: [Int: MediaLadderResponse] = [
            2: Self.ladder(prequels: [Self.item(1, "S1", "TV", 2018)], sequels: [Self.item(3, "S3", "TV", 2023)]),
            1: Self.ladder(prequels: [], sequels: [Self.item(2, "S2", "TV", 2020)])
        ]
        let open = Self.ladder(prequels: [Self.item(2, "S2", "TV", 2020)], sequels: [])
        let walk = await LadderSeasons.walk(from: open, current: LadderChainEntry(mediaId: 3, title: "S3", format: "TV")) { id in
            ladders[id] ?? Self.ladder(prequels: [], sequels: [])
        }
        #expect(walk.proven)
        #expect(walk.entries.map(\.mediaId) == [1, 2, 3])
        let seasons = LadderSeasons.seasons(chain: walk.entries, current: 3)
        #expect(LadderSeasons.currentNumber(seasons.numbered) == 3)
    }

    @Test("Chain walk: a failed or unconfirmed middle hop leaves the chain unnumbered")
    func chainWalkFailedHopIsUnproven() async {
        // The open title is S3; S2's ladder read fails (`fetchMediaLadder` answers `.empty`).
        let open = Self.ladder(prequels: [Self.item(2, "S2", "TV", 2020)], sequels: [])
        let failed = await LadderSeasons.walk(from: open, current: LadderChainEntry(mediaId: 3, title: "S3", format: "TV")) { _ in
            Self.ladder(prequels: [], sequels: [])
        }
        #expect(!failed.proven)
        #expect(failed.entries.map(\.mediaId) == [2, 3])
        // S2's ladder answers but does not name S3 (relations not computed both ways): unproven too.
        let unconfirmed = await LadderSeasons.walk(from: open, current: LadderChainEntry(mediaId: 3, title: "S3", format: "TV")) { _ in
            Self.ladder(prequels: [], sequels: [Self.item(99, "Other", "TV", 2021)])
        }
        #expect(!unconfirmed.proven)
        #expect(LadderSeasons.confirmsLink(Self.ladder(prequels: [], sequels: [Self.item(3, "S3", "TV", 2023)]), from: 3))
        #expect(!LadderSeasons.confirmsLink(Self.ladder(prequels: [], sequels: []), from: 3))
    }

    @Test("The status mark wires every action it is given")
    func statusMarkWiresActions() {
        let mark = DetailStatusMark(entry: nil, kind: .anime, onListSettings: {}, onFavourite: {}, onVerdict: {},
                                    onProviders: {}, onAddToClub: {}, onShare: {})
        for action in DetailStatusAction.allCases {
            #expect(mark.handler(action) != nil, "\(action) has no closure")
        }
        // Optional actions the page did not pass are left out, never shown dead.
        let bare = DetailStatusMark(entry: nil, onListSettings: {}, onFavourite: {}, onVerdict: {}, onProviders: {})
        #expect(bare.handler(.share) == nil)
        #expect(bare.handler(.verdict) != nil)
    }

    @Test("Only shown characters count: a cast of background roles adds no heading")
    func backgroundOnlyCastHidesCharacters() {
        let extra = Character(id: 1, anilistId: nil, nameFull: "Passer-by", nameNative: nil, imageLarge: nil,
                              description: nil, gender: nil, age: nil)
        #expect(DetailCharactersRail.shown([(character: extra, role: "BACKGROUND")]).isEmpty)
        #expect(DetailCharactersRail.shown([(character: extra, role: "MAIN")]).count == 1)
    }

    @Test("Detail load parts: the story shows while reads are pending; the rest after")
    func loadingKeepsLowerSectionsBack() {
        let sections: [DetailSection] = [.hero, .story, .seasons, .progress, .credits]
        #expect(DetailLoadPart.visibleSections(sections, settled: false) == [.story])
        #expect(DetailLoadPart.visibleSections(sections, settled: true) == [.story, .seasons, .progress, .credits])
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
        // Song kickers: "Folge N" / "Folgen N–M" in German, never "F.".
        #expect(DetailSoundPanel.episodes("1–5", german: true) == "Folgen 1–5")
        #expect(DetailSoundPanel.episodes("3", german: true) == "Folge 3")
        #expect(DetailSoundPanel.episodes("1–5", german: false) == "Ep. 1–5")
        // Spoiler rows name the stored scope; no season number exists to show.
        #expect(FriendsActivitySection.spoilerLabel("story", german: false) == "Spoiler · Story")
        #expect(FriendsActivitySection.spoilerLabel("ending", german: true) == "Spoiler · Ende")
        #expect(FriendsActivitySection.spoilerLabel("unknown", german: false) == "Spoiler")
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
