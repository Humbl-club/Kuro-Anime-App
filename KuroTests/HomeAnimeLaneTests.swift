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
        // VoiceOver: the German verb agrees with the number of names.
        #expect(HomeSceneFact.clubSpoken(["Mina"], title: "Frieren", german: true) == "Mina hat über Frieren geschrieben")
        #expect(HomeSceneFact.clubSpoken(["Mina", "Jules"], title: "Frieren", german: true)
                == "Mina + Jules haben über Frieren geschrieben")
        #expect(HomeSceneFact.clubSpoken(["Mina"], title: "Frieren", german: false) == "Mina wrote about Frieren")
    }

    // MARK: Medium word (amendment 7)

    @Test("The art-filled medium word never reads lighter than the unselected word")
    func mediumWordContrastFloor() {
        let canvas = KuroRGB(1, 0xFE / 255, 0xF8 / 255)
        func contrast(_ ink: KuroRGB) -> Double { (canvas.luminance + 0.05) / (ink.luminance + 0.05) }
        // The lightest mean the art band keeps (a neutral grey at the target luma) is darker, so more
        // legible on the canvas, than the unselected word, and still passes AA on its own.
        let target = HomeMediumWordInk.targetLuma
        let lightest = KuroRGB(target, target, target)
        #expect(lightest.luminance < HomeMediumWordInk.unselected.luminance)
        #expect(contrast(lightest) > contrast(HomeMediumWordInk.unselected))
        #expect(contrast(lightest) >= 4.5, "The lightest mean the selected word can have still passes AA.")
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

    // MARK: +1 toast (PROTOTYPE_SPEC.md §3.4, §6)

    /// A real +1 through `HomeStore` (a signed-in account with a progress outbox), then the toast the
    /// page shows for it at the screen foot: "Progress saved." with Undo and the dismiss ×. Rendered on
    /// a 390 × 844 screen, so the toast sits where the reader sees it, over the feed.
    @Test("Home +1: the toast with Undo sits at the screen foot, for the title Home advanced")
    func progressToastRender() async throws {
        Self.seedArtwork()
        let materials = ArtworkMaterialStore(cacheDirectory: nil, loader: Self.fixtureLoader)
        await Self.warm(materials)
        let suite = "home-toast-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = try ProgressOutbox(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suite).sqlite").path)
        // The Library row Home's card stands for (Jujutsu Kaisen, episode 6, the card's lifecycle).
        let backend = FakeLibraryBackend()
        let lifecycle = try #require(UUID(uuidString: "11111113-1111-4111-8111-111111111111"))
        backend.setRows([LibraryEntry(key: MediaKey(kind: .anime, id: 3), rowId: 3, status: .current, progress: 6,
                                      createdAt: Date(), updatedAt: Date(), revision: 2, lifecycleId: lifecycle)],
                        for: LifecycleFixtures.userA)
        let graph = AppComposition.testingGraph(
            testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
            libraryBackend: backend,
            flags: FeatureFlags(userDefaults: defaults, launchArguments: ["--ff-on=series_foundation_v1"]),
            progressOutbox: outbox)
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "home@example.com")
        await graph.libraryActions.libraryRefreshTask?.value
        graph.home.seedForVisualQA(anime: Self.bundle(.busy), manga: nil, medium: "anime")
        graph.releases.schedule = Self.schedule(.busy)
        Self.seedClub(graph)
        let card = try #require(graph.home.bundle?.active.first { $0.mediaId == 3 })
        let before = graph.home.displayedProgress(for: card)
        // Undo through the store puts the count back while the save is still on this device.
        await graph.home.advance(card)
        await graph.home.undo(card)
        #expect(HomeProgressToastCopy.undoResult(before: before, after: graph.home.displayedProgress(for: card)) == .undone)
        await graph.home.advance(card)
        let after = graph.home.displayedProgress(for: card)
        #expect(after == before + 1, "The +1 is saved on this device (\(graph.home.statusMessage ?? "no status")).")
        let account = try #require(graph.accountSession.current)
        let undo = HomeProgressToasts.Undo(medium: "anime", mediaId: card.mediaId, lifecycleId: card.lifecycleId,
                                           before: before, account: account)
        #expect(HomeProgressToasts.undoApplies(undo, lastKey: graph.home.lastAdvancedKey,
                                               lastLifecycle: graph.home.lastAdvancedLifecycle?.uuidString))
        let result = try #require(HomeProgressToastCopy.advanceResult(before: before, after: after,
                                                                      caughtUpAfter: false, saveFailed: false))
        let toasts = HomeProgressToasts(holdSeconds: 60)
        // After the page's first appearance (which resets its presentation for the account), as a tap
        // on the key would be.
        let message = HomeProgressToastCopy.message(result, german: KuroLocale.isGerman)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            toasts.show(message, undo: undo)
        }
        let url = Self.outDir.appendingPathComponent("home-busy-anime-toast\(KuroLocale.isGerman ? "-de" : "")-390.png")
        try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        try await Self.render(Self.home(graph, materials, progressToasts: toasts), width: 390, height: 844, to: url,
                              deviceSafeArea: false)
        #expect(FileManager.default.fileExists(atPath: url.path))
        await graph.session.endSession()
    }

    // MARK: Manga Home through HomeView (Task 10 integration; written only with KURO_WRITE_SNAPSHOTS=1)

    /// The integrated `HomeView` on the manga medium, the four states the manga references show, on the
    /// pager's manga canvas. Same harness and 1 px = 1 pt scale as the anime renders. The German run
    /// (`-testLanguage de -testRegion DE`) writes busy and quiet at 390 with the `-de` suffix.
    @Test("Manga Home fixture renders through HomeView: busy, full, undated and quiet at 320 / 390 / 430")
    func mangaHomeRenders() async throws {
        Self.seedMangaArtwork()
        let materials = ArtworkMaterialStore(cacheDirectory: nil, loader: Self.fixtureLoader)
        await Self.warm(materials, urls: Self.mangaTitles.compactMap { URL(string: Self.artHost + $0.cover) })
        let outDir = Self.mangaOutDir
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let german = KuroLocale.isGerman
        let scenarios: [Scenario] = german ? [.busy, .quiet] : Scenario.allCases
        let widths: [CGFloat] = german ? [390] : [390, 320, 430]
        for scenario in scenarios {
            let graph = try Self.mangaGraph(scenario)
            for width in widths {
                let url = outDir.appendingPathComponent("home-\(scenario.rawValue)-manga\(german ? "-de" : "")-\(Int(width)).png")
                try await Self.render(Self.home(graph, materials, canvas: .kuroCanvasHomeManga), width: width,
                                      height: 2_400, to: url, canvas: .kuroCanvasHomeManga)
                #expect(FileManager.default.fileExists(atPath: url.path))
                // The page fits its width: the gutters' outer 8 pt stay canvas beside the switch, the
                // covers and the calendar (a page laid out wider than the phone is clipped there).
                #expect(Self.edgesAreBlank(url, inset: 8, rows: 0..<900),
                        "\(scenario.rawValue) manga at \(Int(width)) draws into its outer 8 pt")
            }
        }
    }

    private static var mangaOutDir: URL {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-home-manga-integrated", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/prototype-fidelity/native/home-manga", isDirectory: true)
    }

    private static func mangaGraph(_ scenario: Scenario) throws -> AppGraph {
        let defaults = try #require(UserDefaults(suiteName: "home-manga-integrated-\(UUID().uuidString)"))
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        graph.home.seedForVisualQA(anime: nil, manga: Self.mangaBundle(scenario), medium: "manga")
        graph.releases.schedule = Self.mangaSchedule(scenario)
        Self.seedClub(graph)
        return graph
    }

    /// The manga reference's shelf (prototype sample art, fixtures only).
    private static let mangaTitles: [(id: Int, title: String, cover: String)] = [
        (1, "Chainsaw Man", "manga0.jpg"),
        (2, "Solo Leveling", "manga1.jpg"),
        (3, "Jujutsu Kaisen", "manga2.jpg"),
        (4, "Berserk", "manga3.jpg"),
        (5, "SPY x FAMILY", "journal-manga-13-cover.jpg"),
        (6, "Vinland Saga", "journal-manga-16-cover.jpg")
    ]

    private static func mangaCover(_ id: Int) -> String {
        artHost + (mangaTitles.first { $0.id == id }?.cover ?? "manga0.jpg")
    }

    private static func seedMangaArtwork() {
        for row in mangaTitles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + row.cover)),
                  let url = URL(string: artHost + row.cover),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "image/jpeg"]) else { continue }
            URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                                                for: URLRequest(url: url))
        }
    }

    /// Busy, full and undated read Chainsaw Man 24, Solo Leveling 8 (finished at 9: a backlog, never
    /// "new"), Jujutsu Kaisen 19, Berserk 12, SPY x FAMILY 4 and Vinland Saga 40 (the reference's
    /// sixth title is Vagabond; the fixture art is Vinland Saga's cover, so the title follows the art).
    /// Against the dated chapters ahead (26, 22, 6) that is 1 + 2 + 1 = "4 new chapters", the
    /// reference's headline, honestly. Berserk and Vinland Saga are on hiatus: how many chapters are
    /// out is not known, so their keys keep the +1 (as the reference draws them) and they never block
    /// the quiet line. Quiet has read every released chapter (the caught-up account).
    static func mangaBundle(_ scenario: Scenario) -> HomeBundle? {
        let quiet = scenario == .quiet
        func card(_ id: Int, progress: Int, chapters: Int?, status: String) -> String {
            let title = mangaTitles.first { $0.id == id }?.title ?? ""
            return """
            {"media_id":\(id),"list_type":"READING","progress":\(progress),"server_revision":2,
             "lifecycle_id":"2222222\(id)-2222-4222-8222-222222222222","title":"\(title)",
             "cover_image":"\(mangaCover(id))","banner_image":null,"format":"MANGA",
             "chapters":\(chapters.map(String.init) ?? "null"),"catalogue_status":"\(status)"}
            """
        }
        let cards = [
            card(1, progress: quiet ? 25 : 24, chapters: nil, status: "RELEASING"),
            card(2, progress: quiet ? 9 : 8, chapters: 9, status: "FINISHED"),
            card(3, progress: quiet ? 21 : 19, chapters: nil, status: "RELEASING"),
            card(4, progress: 12, chapters: nil, status: "HIATUS"),
            card(5, progress: quiet ? 5 : 4, chapters: nil, status: "RELEASING"),
            card(6, progress: 40, chapters: nil, status: "HIATUS")
        ].joined(separator: ",")
        // The notes are two hours old whenever the suite runs (the references' "2h ago").
        let noteAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7_200))
        let club = """
        {"state":"ready","label":"Sunday Club","items":[
          {"comment_id":"m1","media_id":4,"media_type":"MANGA","text":"Just one more. Famous last words.",
           "display_name":"Mina","spoiler_scope":"none","created_at":"\(noteAt)"},
          {"comment_id":"m3","media_id":4,"media_type":"MANGA","text":null,"display_name":"Mina",
           "spoiler_scope":"ending","created_at":"\(noteAt)"},
          {"comment_id":"m2","media_id":2,"media_type":"MANGA","text":"Started.","display_name":"Jules",
           "spoiler_scope":"none","created_at":"\(noteAt)"}]}
        """
        return try? decode("""
        {"medium":"manga","window_days":7,"home_revision":1,"active":[\(cards)],"upcoming":[],"pending":[],
         "schedule_state":"ok","next_cursor":null,"club":\(club)}
        """)
    }

    /// Manga releases are announced for a day (00:00 UTC of the reader's local day, as stored). Busy and
    /// quiet: three today, two tomorrow, one in a week (the reference's 6 releases · 7 days), plus three
    /// undated volume announcements. Undated: the announcements only. Full: 48 releases on eight days.
    static func mangaSchedule(_ scenario: Scenario) -> [ReleaseScheduleItem] {
        func dayRow(_ days: Int) -> Date {
            let calendar = KuroLocale.calendar
            let start = calendar.startOfDay(for: Date())
            let noon = calendar.date(byAdding: .hour, value: 12, to: calendar.date(byAdding: .day, value: days, to: start) ?? start) ?? start
            let local = calendar.dateComponents([.year, .month, .day], from: noon)
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC") ?? utc.timeZone
            return utc.date(from: local) ?? noon
        }
        func row(_ id: Int, _ unit: ReleaseUnitKind, _ number: Double, _ days: Int?) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: .manga, mediaId: id, title: mangaTitles.first { $0.id == id }?.title ?? "",
                                coverImage: mangaCover(id), unitKind: unit, unitNumber: number,
                                releaseAt: days.map(dayRow), basis: .announced, source: "anilist",
                                precision: days == nil ? nil : .day)
        }
        let undated = [row(4, .volume, 42, nil), row(5, .volume, 14, nil), row(6, .volume, 38, nil)]
        let week = [row(1, .chapter, 26, 0), row(2, .volume, 11, 0), row(3, .chapter, 22, 0),
                    row(4, .chapter, 13, 1), row(5, .chapter, 6, 1), row(6, .chapter, 41, 7)]
        switch scenario {
        case .undated:
            return undated
        case .busy, .quiet:
            return week + undated
        case .full:
            // The reference's 48: six releases on each of eight days over six weeks (today, tomorrow,
            // +4, +7, then four more out to 41 days, so the span reads "6 weeks"): "Show 3 more
            // releases" under today and "Next 4 dates · 24 releases". Each title's chapters (Solo
            // Leveling's volumes) keep counting from the busy numbers, so availability is unchanged.
            let base: [Int: Double] = [1: 26, 2: 11, 3: 22, 4: 13, 5: 6, 6: 41]
            var rows: [ReleaseScheduleItem] = []
            for (index, day) in [0, 1, 4, 7, 14, 21, 28, 41].enumerated() {
                for id in 1...6 {
                    rows.append(row(id, id == 2 ? .volume : .chapter, (base[id] ?? 1) + Double(index), day))
                }
            }
            return rows + undated
        }
    }

    private static func graph(_ scenario: Scenario) throws -> AppGraph {
        let defaults = try #require(UserDefaults(suiteName: "home-anime-lane-\(UUID().uuidString)"))
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        graph.home.seedForVisualQA(anime: Self.bundle(scenario), manga: nil, medium: "anime")
        graph.releases.schedule = Self.schedule(scenario)
        Self.seedClub(graph)
        return graph
    }

    /// The reader's one club (the references' "Sunday Club", active two hours ago), so Home's private
    /// club room shows with the bundle's club notes (`HomeClubRoom.roomNotes` needs exactly one club).
    static func seedClub(_ graph: AppGraph) {
        let iso = ISO8601DateFormatter()
        graph.clubs.myClubs = [
            ClubListRow(id: "fixture-club", name: "Sunday Club", sharing_level: "status", is_archived: false,
                        created_at: "2026-01-01T00:00:00Z", member_count: 3, rail_count: 1, poll_count: 0,
                        last_activity_at: iso.string(from: Date().addingTimeInterval(-7_200)),
                        activity_preview: nil, cover_images: nil, member_names: ["Mina", "Jules", "Ari"],
                        loading_state: nil)
        ]
    }

    static func home(_ graph: AppGraph, _ materials: ArtworkMaterialStore,
                     canvas: Color = .kuroCanvasHome, newAccountLatch: Bool? = nil,
                     progressToasts: HomeProgressToasts? = nil) -> some View {
        HomeView(skipNetworkLoad: true, newAccountLatch: newAccountLatch, progressToasts: progressToasts)
            .environment(graph.home)
            .environment(graph.catalog)
            .environment(graph.library)
            .environment(graph.libraryActions)
            .environment(graph.imports)
            .environment(graph.clubs)
            .environment(graph.discovery)
            .environment(graph.releases)
            .environment(NetworkMonitor())
            .environment(materials)
            .environment(\.kuroRoutes, KuroRoutes.unhandled)
            // The pager's canvas for this medium (`KuroMainView.Section.canvas`).
            .background(canvas)
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

    /// The reference's totals: Demon Slayer 4 / 5 and Attack on Titan 7 / 8 (releasing; the schedule's
    /// next episodes 6 and 9 say 5 and 8 are out, so each has one new episode). Quiet (the reference's
    /// caught-up account): Demon Slayer 5 / 5 and Attack on Titan 8 / 8, Jujutsu Kaisen has watched
    /// the 9 aired, and the finished titles are at their totals, as the reference's ✓ keys show.
    static func bundle(_ scenario: Scenario) -> HomeBundle? {
        let quiet = scenario == .quiet
        let cards = [
            cardJSON(1, progress: quiet ? 5 : 4, episodes: 5, status: "RELEASING", season: 1),
            cardJSON(2, progress: quiet ? 8 : 7, episodes: 8, status: quiet ? "FINISHED" : "RELEASING", season: 2),
            cardJSON(3, progress: quiet ? 9 : 6, episodes: 23, status: "RELEASING", season: 2),
            cardJSON(4, progress: quiet ? 37 : 11, episodes: 37, status: "FINISHED", season: nil),
            cardJSON(5, progress: quiet ? 12 : 3, episodes: 12, status: "FINISHED", season: 2),
            cardJSON(6, progress: quiet ? 64 : 8, episodes: 64, status: "FINISHED", season: nil)
        ].joined(separator: ",")
        // The notes are two hours old whenever the suite runs (the references' "2h ago").
        let noteAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7_200))
        let club = """
        {"state":"ready","label":"Sunday Club","items":[
          {"comment_id":"c1","media_id":4,"media_type":"ANIME","text":"Just one more. Famous last words.",
           "display_name":"Mina","spoiler_scope":"none","created_at":"\(noteAt)"},
          {"comment_id":"c3","media_id":4,"media_type":"ANIME","text":null,"display_name":"Mina",
           "spoiler_scope":"ending","created_at":"\(noteAt)"},
          {"comment_id":"c2","media_id":2,"media_type":"ANIME","text":"Again.","display_name":"Jules",
           "spoiler_scope":"none","created_at":"\(noteAt)"}]}
        """
        return try? decode("""
        {"medium":"anime","window_days":7,"home_revision":1,"active":[\(cards)],"upcoming":[],"pending":[],
         "schedule_state":"ok","next_cursor":null,"club":\(club)}
        """)
    }

    /// The account's schedule on the reader's calendar days, so a render never depends on the hour it
    /// runs at (rows behind now never show). Today's rows sit at 16:00, 17:00, 18:00 … while those are
    /// still ahead, otherwise a few minutes from now (before midnight); later days at noon.
    /// - busy / quiet: three today (Demon Slayer 6, Attack on Titan 9, Jujutsu Kaisen), two tomorrow,
    ///   one in six days (the reference's 6 releases · 7 days), plus three undated announcements. Busy
    ///   leaves Jujutsu Kaisen's row without an episode number (the source did not state one), so how
    ///   many of its episodes are out stays unknown: its key keeps the +1 and it adds nothing to
    ///   "2 new episodes" (the reference's composition, honestly). Quiet numbers it 10.
    /// - full: six releases on each of eight days over six weeks (48), the reference's "Show 3 more
    ///   releases" and "Next 4 dates · 24 releases".
    /// - undated: no dated row. Demon Slayer's next episode (6) and Attack on Titan's (9) are announced
    ///   without a date, which says episodes 5 and 8 are out (`availableUnits`: one before the next
    ///   announced unit), so the page still reads "2 new episodes"; Mob Psycho 100's new season is
    ///   announced too (the reference's three announcements).
    static func schedule(_ scenario: Scenario) -> [ReleaseScheduleItem] {
        let now = Date()
        let calendar = KuroLocale.calendar
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        func at(day: Int, slot: Int) -> Date {
            guard day == 0 else {
                let start = calendar.date(byAdding: .day, value: day, to: today) ?? today
                return start.addingTimeInterval(TimeInterval(12 + slot) * 3_600)
            }
            let fixed = today.addingTimeInterval(TimeInterval(16 + slot) * 3_600)
            if fixed > now.addingTimeInterval(120), fixed < tomorrow { return fixed }
            return min(now.addingTimeInterval(TimeInterval(slot + 1) * 60), tomorrow.addingTimeInterval(-TimeInterval(10 - slot)))
        }
        func row(_ id: Int, _ unit: Double?, day: Int?, slot: Int = 0, kind: ReleaseUnitKind = .episode) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: .anime, mediaId: id, title: titles.first { $0.id == id }?.title ?? "",
                                coverImage: art(id).cover, unitKind: kind, unitNumber: unit,
                                releaseAt: day.map { at(day: $0, slot: slot) },
                                basis: day == nil ? .announced : .confirmed, source: "anilist")
        }
        let undated = [row(4, 1, day: nil), row(5, 1, day: nil), row(6, 1, day: nil)]
        let week = { (jujutsu: Double?) in
            [row(1, 6, day: 0, slot: 0), row(2, 9, day: 0, slot: 1), row(3, jujutsu, day: 0, slot: 2),
             row(4, 38, day: 1, slot: 0), row(5, 13, day: 1, slot: 1), row(6, 65, day: 6)]
        }
        switch scenario {
        case .undated:
            return [row(1, 6, day: nil), row(2, 9, day: nil), row(5, nil, day: nil, kind: .season)]
        case .busy:
            return week(nil) + undated
        case .quiet:
            return week(10) + undated
        case .full:
            // Eight days of six (today, tomorrow, +4, +7, then four more out to six weeks). Jujutsu
            // Kaisen's rows stay unnumbered, as in busy.
            var rows: [ReleaseScheduleItem] = []
            for (index, day) in [0, 1, 4, 7, 14, 21, 28, 41].enumerated() {
                for id in 1...6 {
                    let first: [Int: Double] = [1: 6, 2: 9, 4: 38, 5: 13, 6: 65]
                    let unit = first[id].map { $0 + Double(index) }
                    rows.append(row(id, unit, day: day, slot: id - 1))
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
    static func warm(_ store: ArtworkMaterialStore, urls given: [URL]? = nil) async {
        let urls = given ?? titles.compactMap { URL(string: artHost + ($0.banner ?? $0.cover)) }
        for _ in 0..<100 {
            let ready = urls.allSatisfy { store.material(for: $0, seedHex: nil).method == "art-hue-v1" }
            if ready { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// True when the outer `inset` columns on both sides of the PNG at `url` hold one flat colour (the
    /// canvas) over `rows`: nothing is drawn into the gutters' outer edge.
    static func edgesAreBlank(_ url: URL, inset: Int, rows: Range<Int>) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data?.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4) else { return false }
        func pixel(_ x: Int, _ y: Int) -> [Int] {
            let offset = (y * image.width + x) * 4
            return (0..<3).map { Int(data[offset + $0]) }
        }
        let reference = pixel(0, rows.lowerBound)
        for y in rows where y < image.height {
            for x in Array(0..<inset) + Array((image.width - inset)..<image.width) {
                let value = pixel(x, y)
                if zip(value, reference).contains(where: { abs($0 - $1) > 6 }) { return false }
            }
        }
        return true
    }

    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, to url: URL,
                                canvas: Color = .kuroCanvasHome, deviceSafeArea: Bool = true) async throws {
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        // A screen-sized render (the toast at the screen foot): the page fills the screen as the pager's
        // page does, with no device inset around the frame.
        if !deviceSafeArea { host.safeAreaRegions = [] }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.backgroundColor = UIColor(canvas)
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
