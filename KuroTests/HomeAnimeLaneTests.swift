import CoreGraphics
import ImageIO
import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// Prototype-fidelity Task 4 (Home, anime): the opening line (LANE_AMENDMENTS 3), scene cards, Also
/// watching, the Coming up glance and the medium word's contrast floor (amendment 7), plus fixture
/// renders of the busy / full / undated / quiet anime Home next to `docs/prototype-fidelity/reference`.
@Suite("Home anime lane", .serialized, .timeLimit(.minutes(4)))
@MainActor
struct HomeAnimeLaneTests {
    // MARK: Opening line

    @Test("Opening line copy: new units, caught up, new account, EN and DE")
    func openingLineCopy() {
        #expect(HomeOpeningLine.headline(available: 2, caughtUp: false, newAccount: false, medium: .anime, german: false) == "2 new episodes")
        #expect(HomeOpeningLine.headline(available: 1, caughtUp: false, newAccount: false, medium: .anime, german: false) == "1 new episode")
        #expect(HomeOpeningLine.headline(available: 0, caughtUp: true, newAccount: false, medium: .anime, german: false) == "Keep watching.")
        #expect(HomeOpeningLine.headline(available: 0, caughtUp: false, newAccount: true, medium: .anime, german: false) == "Begin here.")
        #expect(HomeOpeningLine.headline(available: 4, caughtUp: false, newAccount: false, medium: .manga, german: false) == "4 new chapters")
        #expect(HomeOpeningLine.headline(available: 0, caughtUp: true, newAccount: false, medium: .manga, german: false) == "Keep reading.")
        #expect(HomeOpeningLine.quietLine(german: false) == "Nothing new today. Stay at your own pace.")

        #expect(HomeOpeningLine.headline(available: 2, caughtUp: false, newAccount: false, medium: .anime, german: true) == "2 neue Folgen")
        #expect(HomeOpeningLine.headline(available: 1, caughtUp: false, newAccount: false, medium: .manga, german: true) == "1 neues Kapitel")
        #expect(HomeOpeningLine.headline(available: 0, caughtUp: true, newAccount: false, medium: .anime, german: true) == "Weiterschauen.")
        #expect(HomeOpeningLine.headline(available: 0, caughtUp: false, newAccount: true, medium: .anime, german: true) == "Fang hier an.")
        #expect(HomeOpeningLine.quietLine(german: true) == "Heute nichts Neues. Bleib in deinem Tempo.")

        #expect(HomeOpeningLine.kicker(newAccount: false, medium: .anime, german: false) == "Now watching")
        #expect(HomeOpeningLine.kicker(newAccount: false, medium: .manga, german: false) == "Now reading")
        #expect(HomeOpeningLine.kicker(newAccount: true, medium: .anime, german: false) == "Your collection")
    }

    @Test("New-account Home (Task 10): latched new accounts keep the block through Plans; the invitation stays for an empty medium beside an occupied one")
    func newAccountPresentation() {
        func shows(_ latched: Bool?, planned: Bool = true, _ scene: HomeShelfScene, other: Bool = false) -> Bool {
            HomeShelfPolicy.showsNewAccount(latched: latched, onlyPlannedTitles: planned, scene: scene,
                                            otherMediumOccupied: other)
        }
        // Latched new account: the block stays through its own Plans (planned titles only).
        #expect(shows(true, .invitation))
        #expect(shows(true, .saved), "the first one-tap Plan must not unmount the block")
        #expect(shows(true, .invitation, other: true), "a Plan in the other medium keeps the block here too")
        // It gives way to a title in progress, and to an import of anything but planned titles (the
        // Library stays `.loaded` through an import, so the latch itself does not end).
        #expect(!shows(true, .inProgress, other: true))
        #expect(!shows(true, planned: false, .saved), "an import of completed titles ends the block")
        #expect(!shows(true, planned: false, .invitation, other: true),
                "an import into the other medium leaves the approved invitation here")
        // Not latched: an empty medium with the other occupied keeps the approved invitation.
        #expect(!shows(false, .invitation, other: true))
        #expect(!shows(nil, .invitation, other: true))
        #expect(shows(nil, .invitation))
        #expect(!shows(false, .saved))
    }

    @Test("Caught up (amendment 3): the headline is 'Keep watching.' and the quiet line is a separate card")
    func caughtUpQuietCard() {
        let headline = HomeOpeningLine.headline(available: 0, caughtUp: true, newAccount: false, medium: .anime, german: false)
        #expect(headline == "Keep watching.")
        #expect(!headline.contains("Nothing new"), "The quiet line is never folded into the headline.")
        #expect(HomeOpeningLine.showsQuietLine(available: 0, caughtUp: true, newAccount: false))
        #expect(!HomeOpeningLine.showsQuietLine(available: 1, caughtUp: false, newAccount: false))
        #expect(!HomeOpeningLine.showsQuietLine(available: 0, caughtUp: false, newAccount: false),
                "Unknown availability is not caught up: no quiet card.")
        #expect(!HomeOpeningLine.showsQuietLine(available: 0, caughtUp: true, newAccount: true))
    }

    // MARK: Scenes and Also watching

    @Test("Scene card shows at most two titles; the rest go to Also watching")
    func sceneCardsAtMostTwo() throws {
        let cards = try (1...5).map { try Self.card($0, "WATCHING") }
        let lanes = HomeShelfPolicy.scenes(cards)
        #expect(lanes.scenes.map(\.mediaId) == [1, 2])
        #expect(lanes.alsoWatching.map(\.mediaId) == [3, 4, 5])
        let two = HomeShelfPolicy.scenes(Array(cards.prefix(2)))
        #expect(two.scenes.count == 2 && two.alsoWatching.isEmpty)
    }

    @Test("Planned titles never become scene cards or Also watching tiles")
    func plannedNeverScenes() throws {
        let cards = [try Self.card(1, "PLANNING"), try Self.card(2, "WATCHING"), try Self.card(3, "PLANNING"),
                     try Self.card(4, "CURRENT"), try Self.card(5, "PAUSED"), try Self.card(6, "WATCHING")]
        let lanes = HomeShelfPolicy.scenes(cards)
        #expect(lanes.scenes.map(\.mediaId) == [2, 4])
        #expect(lanes.alsoWatching.map(\.mediaId) == [6])
        #expect(!(lanes.scenes + lanes.alsoWatching).contains { $0.listType == "PLANNING" })
    }

    @Test("Season tab omitted when the ladder number is unknown; never an invented Season 1")
    func seasonTabNeedsLadderNumber() {
        #expect(HomeSeasonTab.make(sectionOrdinal: nil, sectionKind: "season", german: false) == nil)
        #expect(HomeSeasonTab.make(sectionOrdinal: nil, sectionKind: nil, german: false) == nil)
        #expect(HomeSeasonTab.make(sectionOrdinal: 0, sectionKind: "season", german: false) == nil)
        #expect(HomeSeasonTab.make(sectionOrdinal: 2, sectionKind: "season", german: false)
                == HomeSeasonTab(word: "Season", number: "2"))
        #expect(HomeSeasonTab.make(sectionOrdinal: 2, sectionKind: "season", german: true)?.word == "Staffel")
        #expect(HomeSeasonTab.make(sectionOrdinal: nil, sectionKind: "film", german: false)
                == HomeSeasonTab(word: nil, number: "Film"))
    }

    @Test("longTitleNeverOverlapsKey: a fixed 44 pt key column; titles wrap to two lines, then truncate")
    func longTitleNeverOverlapsKey() {
        #expect(HomeSceneMetrics.keyColumn == 44)
        #expect(HomeSceneMetrics.sceneTitleLines(accessibility: false) == 2)
        #expect(HomeSceneMetrics.sceneTitleLines(accessibility: true) == 3)
        #expect(HomeSceneMetrics.tileTitleLines(accessibility: false) == 3)
        // At accessibility sizes the readout and key move under the title, and Also watching is one column.
        #expect(HomeSceneMetrics.stacksSceneFoot(accessibility: true))
        #expect(!HomeSceneMetrics.stacksSceneFoot(accessibility: false))
        #expect(HomeSceneMetrics.alsoWatchingColumns(accessibility: false) == 2)
        #expect(HomeSceneMetrics.alsoWatchingColumns(accessibility: true) == 1)
        #expect(HomeSceneMetrics.isCompact(columnWidth: 288))
        #expect(!HomeSceneMetrics.isCompact(columnWidth: 350))
        #expect(!HomeSceneMetrics.isCompact(columnWidth: 0), "Unmeasured is not a small phone.")
    }

    // MARK: Honest availability

    @Test("Released units: finished uses the total, releasing the next known release, else unknown")
    func availabilityIsNeverGuessed() {
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "FINISHED", total: 26, nextUnit: nil) == 26)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "FINISHED", total: nil, nextUnit: nil) == nil)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "RELEASING", total: 12, nextUnit: 6) == 5)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "RELEASING", total: 4, nextUnit: 9) == 4)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "RELEASING", total: nil, nextUnit: 9) == 8)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "RELEASING", total: 12, nextUnit: nil) == nil)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "NOT_YET_RELEASED", total: 12, nextUnit: 1) == nil)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: nil, total: 12, nextUnit: 3) == nil)

        #expect(HomeShelfPolicy.hasNewUnit(progress: 4, available: 5, catalogueStatus: "RELEASING"))
        #expect(!HomeShelfPolicy.hasNewUnit(progress: 4, available: 26, catalogueStatus: "FINISHED"),
                "A finished title's backlog is not new.")
        #expect(!HomeShelfPolicy.hasNewUnit(progress: 5, available: 5, catalogueStatus: "RELEASING"))
        #expect(!HomeShelfPolicy.hasNewUnit(progress: 1, available: nil, catalogueStatus: "RELEASING"))
        #expect(HomeShelfPolicy.isKnownCaughtUp(progress: 5, available: 5))
        #expect(!HomeShelfPolicy.isKnownCaughtUp(progress: 5, available: nil))
    }

    @Test("A volume or season row never decides how many chapters or episodes are out")
    func nextUnitMatchesTheTrackedUnit() {
        func row(_ kind: ReleaseUnitKind, _ number: Double?, basis: ReleaseBasis = .confirmed,
                 medium: MediaKind = .manga) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: medium, mediaId: 1, title: "T", unitKind: kind, unitNumber: number,
                                releaseAt: Date(timeIntervalSince1970: 1_900_000_000), basis: basis, source: "anilist")
        }
        #expect(HomeShelfPolicy.nextUnitNumber([row(.volume, 11)], medium: .manga) == nil)
        #expect(HomeShelfPolicy.nextUnitNumber([row(.volume, 11), row(.chapter, 81)], medium: .manga) == 81)
        #expect(HomeShelfPolicy.nextUnitNumber([row(.chapter, 81, basis: .estimated)], medium: .manga) == nil)
        #expect(HomeShelfPolicy.nextUnitNumber([row(.chapter, 81.5)], medium: .manga) == nil)
        #expect(HomeShelfPolicy.nextUnitNumber([row(.season, 3, medium: .anime)], medium: .anime) == nil)
        #expect(HomeShelfPolicy.nextUnitNumber([row(.episode, 9, medium: .anime)], medium: .anime) == 9)
        // A releasing manga at ch. 80 whose only row is "Volume 11" stays unknown: never caught up.
        let available = HomeShelfPolicy.availableUnits(
            catalogueStatus: "RELEASING", total: nil,
            nextUnit: HomeShelfPolicy.nextUnitNumber([row(.volume, 11)], medium: .manga))
        #expect(available == nil)
        #expect(!HomeShelfPolicy.isKnownCaughtUp(progress: 80, available: available))
    }

    // MARK: Opening composition (every title in progress, units not titles)

    private func entry(_ progress: Int, _ available: Int?, _ status: String?) -> HomeShelfPolicy.OpeningEntry {
        HomeShelfPolicy.OpeningEntry(progress: progress, available: available, catalogueStatus: status)
    }

    @Test("Opening: counts released units over every title in progress; finished backlogs never count")
    func openingCountsUnitsOverAllTitles() {
        // The busy fixture: two scenes one behind each, JJK caught up, finished backlogs.
        let busy = HomeShelfPolicy.opening([entry(4, 5, "RELEASING"), entry(7, 8, "RELEASING"), entry(6, 6, "RELEASING"),
                                            entry(11, 37, "FINISHED"), entry(3, 12, "FINISHED")])
        #expect(busy.newUnits == 2 && !busy.nothingNew)
        // A title three episodes behind adds three, not one.
        #expect(HomeShelfPolicy.opening([entry(2, 5, "RELEASING")]).newUnits == 3)
        // Two caught-up scenes plus an Also watching title with a new episode: 1, and no quiet card.
        let alsoNew = HomeShelfPolicy.opening([entry(5, 5, "RELEASING"), entry(8, 8, "FINISHED"), entry(6, 7, "RELEASING")])
        #expect(alsoNew.newUnits == 1 && !alsoNew.nothingNew)
        #expect(HomeOpeningLine.headline(available: alsoNew.newUnits, caughtUp: alsoNew.nothingNew, newAccount: false,
                                         medium: .anime, german: false) == "1 new episode")
        #expect(!HomeOpeningLine.showsQuietLine(available: alsoNew.newUnits, caughtUp: alsoNew.nothingNew, newAccount: false))
        // Manga sums chapters across books.
        let manga = HomeShelfPolicy.opening([entry(20, 24, "RELEASING"), entry(80, 81, "RELEASING")])
        #expect(HomeOpeningLine.headline(available: manga.newUnits, caughtUp: manga.nothingNew, newAccount: false,
                                         medium: .manga, german: false) == "5 new chapters")
    }

    @Test("Quiet card: nothing new and nothing unknown; finished backlogs never block it")
    func quietCardNeedsKnownAvailability() {
        // Caught up to aired, a finished backlog (11 / 37) and a not-yet-released title: quiet.
        let quiet = HomeShelfPolicy.opening([entry(5, 5, "RELEASING"), entry(11, 37, "FINISHED"), entry(0, nil, "NOT_YET_RELEASED"),
                                             entry(4, nil, "HIATUS")])
        #expect(quiet.newUnits == 0 && quiet.nothingNew)
        #expect(HomeOpeningLine.showsQuietLine(available: quiet.newUnits, caughtUp: quiet.nothingNew, newAccount: false))
        // A releasing title whose released count is unknown: never "nothing new".
        let unknown = HomeShelfPolicy.opening([entry(5, 5, "RELEASING"), entry(3, nil, "RELEASING")])
        #expect(unknown.newUnits == 0 && !unknown.nothingNew)
        #expect(!HomeShelfPolicy.opening([entry(5, 5, "RELEASING"), entry(3, nil, nil)]).nothingNew,
                "A title Home knows no status for may be releasing: unknown.")
        #expect(!HomeShelfPolicy.opening([]).nothingNew)
    }

    @Test("Home key: caught up at the total, or at the released count (the next episode has not aired)")
    func homeKeyGatesUnairedEpisodes() {
        // Busy-style title: total 12, 5 aired, 5 watched: the ✓, never a +1 for unaired episode 6.
        #expect(HomeShelfPolicy.homeKeyCaughtUp(progress: 5, total: 12, available: 5))
        #expect(!HomeShelfPolicy.homeKeyCaughtUp(progress: 4, total: 12, available: 5))
        #expect(HomeShelfPolicy.homeKeyCaughtUp(progress: 12, total: 12, available: nil))
        // Unknown availability keeps the +1 (never a guessed cap).
        #expect(!HomeShelfPolicy.homeKeyCaughtUp(progress: 5, total: 12, available: nil))
        #expect(!HomeShelfPolicy.homeKeyCaughtUp(progress: 5, total: nil, available: nil))
        // The fact row reads the same rule, so "Up to date" never sits beside a live +1.
        let caughtUp = HomeShelfPolicy.homeKeyCaughtUp(progress: 5, total: 12, available: 5)
        #expect(HomeSceneFact.make(hasNew: false, knownCaughtUp: caughtUp, clubNames: [], medium: .anime, german: false)
                == .upToDate("Up to date"))
    }

    @Test("The +1 stamp plays only after a raised save, for the same account presentation and medium")
    func stampRule() {
        #expect(HomeShelfPolicy.shouldStamp(before: 4, after: 5, ticketCurrent: true, mediumUnchanged: true))
        #expect(!HomeShelfPolicy.shouldStamp(before: 4, after: 4, ticketCurrent: true, mediumUnchanged: true),
                "A refused or failed save never stamps.")
        #expect(!HomeShelfPolicy.shouldStamp(before: 4, after: 5, ticketCurrent: false, mediumUnchanged: true),
                "The account changed during the save: never stamp the new account's title.")
        #expect(!HomeShelfPolicy.shouldStamp(before: 4, after: 5, ticketCurrent: true, mediumUnchanged: false))
    }

    @Test("Club names: same id AND same medium; real names only, no repeats")
    func clubNamesMatchTheMedium() throws {
        let items: [HomeClubItem] = try Self.decode("""
        [{"comment_id":"a","media_id":2,"media_type":"ANIME","display_name":"Mina"},
         {"comment_id":"b","media_id":2,"media_type":"MANGA","display_name":"Noah"},
         {"comment_id":"c","media_id":2,"media_type":"ANIME","display_name":" "},
         {"comment_id":"d","media_id":2,"media_type":"ANIME","display_name":"Mina"},
         {"comment_id":"e","media_id":3,"media_type":"ANIME","display_name":"Ari"}]
        """)
        #expect(HomeShelfPolicy.clubNames(items, mediaId: 2, medium: "anime") == ["Mina"])
        #expect(HomeShelfPolicy.clubNames(items, mediaId: 2, medium: "manga") == ["Noah"],
                "A manga note with the same id never lands on the anime scene.")
    }

    @Test("Scene footer: one honest fact, else nothing; club names only when real")
    func sceneFact() {
        // Real club names rank first (the prototype's second scene carries the club link in every state).
        #expect(HomeSceneFact.make(hasNew: true, knownCaughtUp: false, clubNames: ["Mina"], medium: .anime, german: false)
                == .club(names: ["Mina"]))
        #expect(HomeSceneFact.make(hasNew: false, knownCaughtUp: true, clubNames: ["Mina", "Jules"], medium: .anime, german: false)
                == .club(names: ["Mina", "Jules"]))
        #expect(HomeSceneFact.make(hasNew: true, knownCaughtUp: false, clubNames: [], medium: .anime, german: false)
                == .newUnit("New episode available"))
        #expect(HomeSceneFact.make(hasNew: false, knownCaughtUp: true, clubNames: [], medium: .anime, german: false)
                == .upToDate("Up to date"))
        #expect(HomeSceneFact.make(hasNew: false, knownCaughtUp: true, clubNames: [], medium: .anime, german: true)
                == .upToDate(KuroAdvanceCopy.caughtUpLabel(title: nil, german: true)),
                "German: one caught-up string for the fact, the readout and the key.")
        #expect(HomeSceneFact.make(hasNew: false, knownCaughtUp: false, clubNames: ["Mina", "Jules", "Noah"], medium: .anime, german: false)
                == .club(names: ["Mina", "Jules"]))
        #expect(HomeSceneFact.make(hasNew: false, knownCaughtUp: false, clubNames: [], medium: .anime, german: false) == nil)
        #expect(HomeSceneFact.make(hasNew: true, knownCaughtUp: false, clubNames: [], medium: .anime, german: true)
                == .newUnit("Neue Folge verfügbar"))
        #expect(HomeSceneFact.clubLine(["Mina", "Jules"]) == "Mina + Jules")
        #expect(HomeAlsoWatchingHeading.countLine(4, german: false) == "4 titles")
        #expect(HomeAlsoWatchingHeading.countLine(1, german: false) == "1 title")
        #expect(HomeAlsoWatchingHeading.countLine(4, german: true) == "4 Titel")
        #expect(HomeAlsoWatchingHeading.title(medium: .anime, german: true) == "Schaust du auch")
    }

    // MARK: Medium word (amendment 7)

    @Test("The art-filled medium word never reads lighter than the unselected word")
    func mediumWordContrastFloor() {
        let canvas = KuroRGB(1, 0xFE / 255, 0xF8 / 255)
        func contrast(_ ink: KuroRGB) -> Double { (canvas.luminance + 0.05) / (ink.luminance + 0.05) }
        #expect(HomeMediumWordInk.floor.luminance < HomeMediumWordInk.unselected.luminance)
        #expect(contrast(HomeMediumWordInk.floor) > contrast(HomeMediumWordInk.unselected))
        #expect(contrast(HomeMediumWordInk.floor) >= 4.5, "The lightest the selected word can be still passes AA.")
        #expect(HomeMediumWordInk.unselected.hex.lowercased() == "#6e786f")
    }

    // MARK: Coming up glance

    @Test("Glance: the first day and its count, undated pending, honest states with nothing to count")
    func glanceSummary() throws {
        let now = Date(timeIntervalSince1970: 1_791_979_200) // Wed 14 Oct 2026, 12:00 UTC
        let copy = ReleaseCopy(now: now, german: false, locale: Locale(identifier: "en_GB"),
                               timeZone: try #require(TimeZone(identifier: "Europe/Berlin")))
        func row(_ id: Int, _ at: Date?) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: .anime, mediaId: id, title: "T\(id)", unitKind: .episode, unitNumber: 2,
                                releaseAt: at, basis: at == nil ? .announced : .confirmed, source: "anilist")
        }
        let today = [row(1, now.addingTimeInterval(1_800)), row(2, now.addingTimeInterval(3_600)),
                     row(3, now.addingTimeInterval(5_400))]
        let busy = today + [row(4, now.addingTimeInterval(86_400)), row(5, nil)]
        let summary = HomeGlanceSummary.make(items: busy, copy: copy, offline: false, coverage: .complete, checked: true)
        #expect(summary.caption == "Today · 3 releases")
        #expect(summary.count == 4 && summary.countLabel == "this week")
        let busyGroups = HomeCalendarPresentation.groups(busy, copy: copy)
        #expect(HomeCalendarPresentation.summary(busyGroups, coverage: .complete, copy: copy) == "4 releases · 7 days")

        // Full: every dated release the calendar lists, labelled by how far ahead they reach.
        let full = today + (1...5).map { row(10 + $0, now.addingTimeInterval(Double($0) * 8 * 86_400)) }
        let fullSummary = HomeGlanceSummary.make(items: full, copy: copy, offline: false, coverage: .complete, checked: true)
        #expect(fullSummary.count == 8 && fullSummary.countLabel == "6 weeks", "40 days ahead reads 6 weeks.")
        #expect(HomeCalendarPresentation.summary(HomeCalendarPresentation.groups(full, copy: copy), coverage: .complete,
                                                  copy: copy) == "8 releases · 6 weeks")
        #expect(fullSummary.countLabel != "later", "Never the invented 'later'.")
        // The airing fallback knows seven days only.
        #expect(HomeGlanceSummary.make(items: full, copy: copy, offline: false, coverage: .nextSevenDays, checked: true)
                .countLabel == "this week")
        // A month window has no honest span in days: no label, and the summary states the count only.
        let month = ReleaseScheduleItem(medium: .anime, mediaId: 30, title: "M", unitKind: .episode, unitNumber: 1,
                                        releaseAt: now.addingTimeInterval(60 * 86_400), basis: .announced,
                                        source: "anilist", precision: .month)
        let windowed = HomeGlanceSummary.make(items: today + [month], copy: copy, offline: false, coverage: .complete, checked: true)
        #expect(windowed.count == 4 && windowed.countLabel == nil)
        #expect(HomeCalendarPresentation.summary(HomeCalendarPresentation.groups(today + [month], copy: copy),
                                                  coverage: .complete, copy: copy) == "4 releases")
        #expect(HomeCalendarPresentation.summary([], coverage: .complete, copy: copy) == "From your list")
        #expect(summary.art.map(\.mediaId) == [1, 2, 3])
        #expect(summary.linksToCalendar)

        let undated = HomeGlanceSummary.make(items: [row(7, nil), row(8, nil)], copy: copy, offline: false,
                                             coverage: .complete, checked: true)
        #expect(undated.caption == "Dates still to come")
        #expect(undated.count == 2 && undated.countLabel == "pending")

        let unchecked = HomeGlanceSummary.make(items: [], copy: copy, offline: false, coverage: .pending, checked: false)
        #expect(unchecked.caption == "Checking dates" && unchecked.count == nil && !unchecked.linksToCalendar)
        let nothing = HomeGlanceSummary.make(items: [], copy: copy, offline: false, coverage: .complete, checked: true)
        #expect(nothing.caption == "Nothing scheduled" && nothing.count == nil)
        let failed = HomeGlanceSummary.make(items: [], copy: copy, offline: false, coverage: .failed, checked: true)
        #expect(failed.caption == "Couldn't load dates", "A failed read is never 'nothing scheduled'.")

        let german = ReleaseCopy(now: now, german: true, locale: Locale(identifier: "de_DE"),
                                 timeZone: try #require(TimeZone(identifier: "Europe/Berlin")))
        let de = HomeGlanceSummary.make(items: busy, copy: german, offline: false, coverage: .complete, checked: true)
        #expect(de.caption == "Heute · 3 Veröffentlichungen" && de.countLabel == "diese Woche")
        #expect(HomeGlanceSummary.make(items: full, copy: german, offline: false, coverage: .complete, checked: true)
                .countLabel == "6 Wochen")
        #expect(HomeCalendarPresentation.summary(HomeCalendarPresentation.groups(busy, copy: german), coverage: .complete,
                                                  copy: german) == "4 Veröffentlichungen · 7 Tage")
        #expect(HomeCalendarPresentation.summary([], coverage: .complete, copy: german) == "Aus deiner Liste")
    }

    // MARK: Fixture renders (evidence; written only with TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1)

    enum Scenario: String, CaseIterable { case busy, full, undated, quiet }

    /// English: the four states at 320 / 390 / 430 plus busy at AX5. Run again with
    /// `xcodebuild test -testLanguage de -testRegion DE` for the German renders (busy and quiet at 390,
    /// suffix `-de`); KuroLocale reads the run's language, so nothing persists `AppleLanguages`.
    @Test("Anime Home fixture renders: busy, full, undated and quiet at 320 / 390 / 430, AX5 and German")
    func animeHomeRenders() async throws {
        Self.seedArtwork()
        let materials = ArtworkMaterialStore(cacheDirectory: nil, loader: Self.fixtureLoader)
        await Self.warm(materials)
        let outDir = Self.outDir
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let german = KuroLocale.isGerman
        let scenarios: [Scenario] = german ? [.busy, .quiet] : Scenario.allCases
        let widths: [CGFloat] = german ? [390] : [390, 320, 430]
        for scenario in scenarios {
            let graph = try Self.graph(scenario)
            for width in widths {
                let url = outDir.appendingPathComponent("home-\(scenario.rawValue)-anime\(german ? "-de" : "")-\(Int(width)).png")
                try await Self.render(Self.home(graph, materials), width: width, height: 2_300, to: url)
                #expect(FileManager.default.fileExists(atPath: url.path))
            }
        }
        guard !german else { return }
        // AX5: the app's type scale (`KuroTypeScale`, read by every `kuroCustom` size) and the
        // environment both at accessibility 5, then restored.
        let graph = try Self.graph(.busy)
        let savedCategory = KuroTypeScale.current.category
        KuroTypeScale.current.update(.accessibility5)
        defer { KuroTypeScale.current.update(category: savedCategory ?? .large) }
        let url = outDir.appendingPathComponent("home-busy-anime-ax5-390.png")
        try await Self.render(Self.home(graph, materials).environment(\.dynamicTypeSize, .accessibility5),
                              width: 390, height: 4_000, to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    private static func graph(_ scenario: Scenario) throws -> AppGraph {
        let defaults = try #require(UserDefaults(suiteName: "home-anime-lane-\(UUID().uuidString)"))
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        graph.home.seedForVisualQA(anime: Self.bundle(scenario), manga: nil, medium: "anime")
        graph.releases.schedule = Self.schedule(scenario)
        return graph
    }

    private static func home(_ graph: AppGraph, _ materials: ArtworkMaterialStore) -> some View {
        HomeView(skipNetworkLoad: true)
            .environment(graph.home)
            .environment(graph.library)
            .environment(graph.libraryActions)
            .environment(graph.imports)
            .environment(graph.clubs)
            .environment(graph.discovery)
            .environment(graph.releases)
            .environment(NetworkMonitor())
            .environment(materials)
            .environment(\.kuroRoutes, KuroRoutes.unhandled)
            .background(Color.kuroCanvasHome)
            // The pager places Home under the header, never under the status bar.
            .ignoresSafeArea()
    }

    // MARK: Fixture support

    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static var outDir: URL {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-home-anime-lane", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/prototype-fidelity/native/home-anime", isDirectory: true)
    }

    static func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func card(_ id: Int, _ listType: String) throws -> HomeCard {
        try decode("""
        {"media_id":\(id),"list_type":"\(listType)","progress":1,"server_revision":1,
         "lifecycle_id":"11111111-1111-4111-8111-11111111111\(id % 10)","title":"T\(id)"}
        """)
    }

    private static let artHost = "https://visual-fixture.invalid/"

    /// Prototype sample art (fixtures only): scene banners and covers from tools/design-directions/assets.
    private static let titles: [(id: Int, title: String, cover: String, banner: String?)] = [
        (1, "Demon Slayer", "anime1.jpg", "anime1-banner.jpg"),
        (2, "Attack on Titan", "anime0.jpg", "anime0-banner.jpg"),
        (3, "Jujutsu Kaisen", "anime2.jpg", nil),
        (4, "Death Note", "anime3.jpg", "anime3-banner.jpg"),
        (5, "Mob Psycho 100", "journal-anime-22-cover.jpg", "journal-anime-22-banner.jpg"),
        (6, "Fullmetal Alchemist: Brotherhood", "journal-anime-12-cover.jpg", nil)
    ]

    private static func art(_ id: Int) -> (cover: String, banner: String?) {
        let row = titles.first { $0.id == id }
        return (artHost + (row?.cover ?? "anime1.jpg"), row?.banner.map { artHost + $0 })
    }

    private static func cardJSON(_ id: Int, progress: Int, episodes: Int, status: String, season: Int?) -> String {
        let row = titles.first { $0.id == id }
        let artwork = art(id)
        let banner = artwork.banner.map { "\"\($0)\"" } ?? "null"
        let section = season.map { ",\"section_ordinal\":\($0),\"section_kind\":\"season\",\"section_name\":\"Season \($0)\"" } ?? ""
        return """
        {"media_id":\(id),"list_type":"WATCHING","progress":\(progress),"server_revision":2,
         "lifecycle_id":"1111111\(id)-1111-4111-8111-111111111111","title":"\(row?.title ?? "")",
         "cover_image":"\(artwork.cover)","banner_image":\(banner),"format":"TV","episodes":\(episodes),
         "catalogue_status":"\(status)"\(section)}
        """
    }

    /// Quiet (the reference's caught-up account): Demon Slayer has watched every aired episode of 12
    /// (the next one is still ahead: the schedule-gated ✓ and "Caught up 5 / 12"), Attack on Titan is
    /// finished at 8 / 8, Jujutsu Kaisen has watched the 9 aired, and the finished titles are at their
    /// totals, as the reference's ✓ keys show.
    static func bundle(_ scenario: Scenario) -> HomeBundle? {
        let quiet = scenario == .quiet
        let cards = [
            cardJSON(1, progress: quiet ? 5 : 4, episodes: 12, status: "RELEASING", season: 1),
            cardJSON(2, progress: quiet ? 8 : 7, episodes: quiet ? 8 : 12, status: quiet ? "FINISHED" : "RELEASING", season: 2),
            cardJSON(3, progress: quiet ? 9 : 6, episodes: 23, status: "RELEASING", season: 2),
            cardJSON(4, progress: quiet ? 37 : 11, episodes: 37, status: "FINISHED", season: nil),
            cardJSON(5, progress: quiet ? 12 : 3, episodes: 12, status: "FINISHED", season: 2),
            cardJSON(6, progress: quiet ? 64 : 8, episodes: 64, status: "FINISHED", season: nil)
        ].joined(separator: ",")
        let club = """
        {"state":"ready","label":"Sunday Club","items":[
          {"comment_id":"c1","media_id":2,"media_type":"ANIME","text":"Famous last words.","display_name":"Mina",
           "spoiler_scope":"none","created_at":"2026-10-01T00:00:00Z"},
          {"comment_id":"c2","media_id":2,"media_type":"ANIME","text":"Again.","display_name":"Jules",
           "spoiler_scope":"none","created_at":"2026-10-01T00:00:00Z"}]}
        """
        return try? decode("""
        {"medium":"anime","window_days":7,"home_revision":1,"active":[\(cards)],"upcoming":[],"pending":[],
         "schedule_state":"ok","next_cursor":null,"club":\(club)}
        """)
    }

    /// The account's schedule relative to now (rows behind now never show). Quiet keeps the busy dates;
    /// the caught-up titles' next episodes are still ahead. Busy and full: Jujutsu Kaisen's rows carry no
    /// episode number (the source did not state one), so how many episodes are out stays unknown: its
    /// key keeps the +1 and it adds nothing to "2 new episodes" (the reference's composition, honestly).
    static func schedule(_ scenario: Scenario) -> [ReleaseScheduleItem] {
        let now = Date()
        func row(_ id: Int, _ unit: Double?, _ offset: TimeInterval?) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: .anime, mediaId: id, title: titles.first { $0.id == id }?.title ?? "",
                                coverImage: art(id).cover, unitKind: .episode, unitNumber: unit,
                                releaseAt: offset.map { now.addingTimeInterval($0) },
                                basis: offset == nil ? .announced : .confirmed, source: "anilist")
        }
        let hour: TimeInterval = 3_600, day: TimeInterval = 86_400
        let undated = [row(4, 1, nil), row(5, 1, nil), row(6, 1, nil)]
        switch scenario {
        case .undated:
            return undated
        case .busy:
            return [row(1, 6, 0.2 * hour), row(2, 9, 0.4 * hour), row(3, nil, 0.6 * hour),
                    row(4, 38, day), row(5, 13, day + hour), row(6, 65, 6 * day)] + undated
        case .quiet:
            return [row(1, 6, 0.2 * hour), row(2, 9, 0.4 * hour), row(3, 10, 0.6 * hour),
                    row(4, 38, day), row(5, 13, day + hour), row(6, 65, 6 * day)] + undated
        case .full:
            // The reference's 48 dated releases: six today, then seven a week for six weeks (the last
            // about 41 days ahead, so the span reads "6 weeks").
            var rows = [row(1, 6, 0.2 * hour), row(2, 9, 0.4 * hour), row(3, nil, 0.6 * hour),
                        row(4, 38, 0.8 * hour), row(5, 13, 1.0 * hour), row(6, 65, 1.2 * hour)]
            for week in 1...6 {
                let start = Double(week * 7 - 1) * day
                for slot in 0..<7 {
                    let id = slot % 6 + 1
                    let unit: Double? = id == 3 ? nil : Double(6 + week * 2 + slot / 6 + id)
                    rows.append(row(id, unit, start + Double(slot) * hour))
                }
            }
            return rows + undated
        }
    }

    /// Images go through `KuroCachedAsyncImage` → URLCache: store each fixture under its fixture URL.
    static func seedArtwork() {
        for row in titles {
            for name in [row.cover] + (row.banner.map { [$0] } ?? []) {
                guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + name)),
                      let url = URL(string: artHost + name),
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                     headerFields: ["Content-Type": "image/jpeg"]) else { continue }
                URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                                                    for: URLRequest(url: url))
            }
        }
    }

    /// The material loader for fixtures: reads the asset named by the URL's last path component.
    nonisolated static let fixtureLoader: ArtworkMaterialStore.Loader = { url in
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/design-directions/assets/" + url.lastPathComponent)
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Asks for every fixture material and waits (≤ 5 s) until each one is derived.
    static func warm(_ store: ArtworkMaterialStore) async {
        let urls = titles.compactMap { URL(string: artHost + ($0.banner ?? $0.cover)) }
        for _ in 0..<100 {
            let ready = urls.allSatisfy { store.material(for: $0, seedHex: nil).method == "art-hue-v1" }
            if ready { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, to url: URL) async throws {
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.backgroundColor = UIColor(Color.kuroCanvasHome)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1_200))
        host.view.layoutIfNeeded()
        // 1 px = 1 pt, as the reference captures (PROTOTYPE_SPEC.md §1).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            // A very tall hierarchy (AX5) can be refused by the render server: fall back to the layer.
            if !host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) {
                host.view.layer.render(in: context.cgContext)
            }
        }
        guard let data = image.pngData() else {
            Issue.record("png encode failed for \(url.lastPathComponent)")
            return
        }
        try data.write(to: url)
    }
}
