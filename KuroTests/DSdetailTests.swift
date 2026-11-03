import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

/// Pure rules of the detail lane (details-songs spec §5.1, §5.3, §6.2–§6.8, §7, §15): the edge-peek
/// table, the facts parts, the next-row words and visibility, the bell's eligibility, the wrong-season
/// still guard, the timeline's rows, the cast rail's members, More like this's filter and the
/// VoiceOver labels. (The spec names this suite `DetailsPassDetailTests`; the lane brief names the
/// file DSdetailTests.)
@Suite("DS detail lane rules")
struct DSdetailTests {
    private static let en = Locale(identifier: "en_GB")
    private static let de = Locale(identifier: "de_DE")
    private static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    private static func item(_ number: Double?, kind: ReleaseUnitKind = .episode, at: Date?, basis: ReleaseBasis,
                             precision: ReleasePrecision? = .instant, isPast: Bool = false) -> ReleaseScheduleItem {
        ReleaseScheduleItem(medium: kind == .episode ? .anime : .manga, mediaId: 7, title: "Title", unitKind: kind,
                            unitNumber: number, releaseAt: at, basis: basis, confidence: 0.95, source: "anilist",
                            isPast: isPast, precision: precision)
    }

    // MARK: §5.1 Edge peek

    @Test("Edge peek: the spec's value table (cards, width, slice)", arguments: [
        (366.0, 3, 98.0, 30.0), (370.0, 3, 100.0, 28.0), (304.0, 2, 112.0, 52.0), (410.0, 3, 112.0, 32.0), (660.0, 5, 112.0, 30.0),
    ])
    func peekTable(visible: Double, cards: Int, width: Double, slice: Double) {
        let v = CGFloat(visible)
        #expect(KuroRailPeek.cardWidth(visible: v) == CGFloat(width))
        #expect(KuroRailPeek.cardsShown(visible: v) == cards)
        #expect(KuroRailPeek.slice(visible: v) == CGFloat(slice))
    }

    @Test("Edge peek: covers are 2 : 3, an unmeasured rail uses the preferred width")
    func peekCover() {
        #expect(KuroRailPeek.coverHeight(width: 98) == 147)
        #expect(KuroRailPeek.cardWidth(visible: 0) == 100)
        #expect(KuroRailPeek.spacing == 14)
    }

    // MARK: §6.2 / §7.2 Facts

    @Test("Anime facts: year, format, episodes, studio, score; missing parts dropped")
    func animeFacts() {
        let parts = DetailFacts.anime(year: 2023, format: "TV", episodes: 23, studio: "MAPPA", averageScore: 86,
                                      german: false, locale: Self.en)
        #expect(DetailFacts.line(parts) == "2023 · TV · 23 episodes · MAPPA · Score 8.6")
        #expect(parts.last?.isScore == true)
        #expect(DetailFacts.spoken(parts) == "2023, TV, 23 episodes, MAPPA, Score 8.6")
        let german = DetailFacts.anime(year: 2023, format: "TV_SHORT", episodes: 1, studio: nil, averageScore: 86,
                                       german: true, locale: Self.de)
        #expect(DetailFacts.line(german) == "2023 · TV-Kurzserie · 1 Folge · Wertung 8,6")
        // A releasing title without a total, no score, an unknown format: nothing invented.
        let sparse = DetailFacts.anime(year: nil, format: "WEIRD", episodes: nil, studio: "  ", averageScore: 0,
                                       german: false, locale: Self.en)
        #expect(sparse.isEmpty)
        #expect(DetailFacts.animeYear(seasonYear: nil, startDateYear: 2019) == 2019)
        #expect(DetailFacts.animeYear(seasonYear: 2020, startDateYear: 2019) == 2020)
    }

    @Test("Manga facts: chapters only when finished; status words EN/DE")
    func mangaFacts() {
        let ongoing = DetailFacts.manga(year: 2018, format: "MANGA", status: "RELEASING", volumes: 18, chapters: 200,
                                        averageScore: 85, german: false, locale: Self.en)
        #expect(DetailFacts.line(ongoing) == "2018 · Manga · Ongoing · 18 volumes · Score 8.5")
        let finished = DetailFacts.manga(year: 2009, format: "LIGHT_NOVEL", status: "FINISHED", volumes: 1, chapters: 40,
                                         averageScore: nil, german: true, locale: Self.de)
        #expect(DetailFacts.line(finished) == "2009 · Light Novel · Abgeschlossen · 1 Band · 40 Kapitel")
        #expect(DetailFacts.mangaStatusWord("HIATUS", german: false) == "On hiatus")
        #expect(DetailFacts.mangaFormatWord("ONE_SHOT", german: true) == "One-Shot")
        #expect(DetailFacts.mangaFormatWord("NOVEL", german: true) == "Roman")
    }

    // MARK: §6.2 Next row, §5.3 marks

    @Test("Next row: shown for an unfinished title with a row ahead; kicker, day count and marks")
    func nextRow() {
        let row = Self.item(8, at: Date().addingTimeInterval(86_400), basis: .confirmed)
        #expect(DetailNextRelease.showsRow(status: "RELEASING", upcoming: row))
        #expect(!DetailNextRelease.showsRow(status: "FINISHED", upcoming: row))
        #expect(!DetailNextRelease.showsRow(status: "RELEASING", upcoming: nil))
        #expect(DetailNextRelease.kicker(.episode, german: false) == "NEXT EPISODE")
        #expect(DetailNextRelease.kicker(.chapter, german: true) == "NÄCHSTES KAPITEL")
        #expect(DetailNextRelease.kicker(.volume, german: true) == "NÄCHSTER BAND")
        #expect(DetailNextRelease.dayCount(0, german: false) == "today")
        #expect(DetailNextRelease.dayCount(1, german: true) == "morgen")
        #expect(DetailNextRelease.dayCount(4, german: true) == "in 4 Tagen")
        #expect(DetailNextRelease.dayCount(nil, german: false) == nil)
        #expect(DetailNextRelease.dayCount(-1, german: false) == nil)
        #expect(DetailNextRelease.markWord(.confirmed, german: false) == "Confirmed")
        #expect(DetailNextRelease.markWord(.announced, german: true) == "Angekündigt")
        #expect(DetailNextRelease.markWord(.estimated, german: true) == "Schätzung")
        // An undated row has no mark (it says "Dates to come.").
        #expect(!DetailNextRelease.showsMark(Self.item(9, at: nil, basis: .announced, precision: nil)))
    }

    @Test("Next row VoiceOver value: the basis word and the source")
    func nextRowSpoken() {
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let copy = ReleaseCopy(now: now, german: false, locale: Self.en, timeZone: Self.berlin)
        let row = Self.item(8, at: now.addingTimeInterval(3 * 86_400), basis: .confirmed)
        #expect(DetailNextRelease.spokenValue(row, copy: copy) == "Confirmed, via AniList")
    }

    // MARK: §11.2 D14 bell

    @Test("Bell: only a confirmed or announced exact time, more than a minute ahead, on a followed title")
    func bellEligibility() {
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let soon = now.addingTimeInterval(3_600)
        #expect(DetailReminderRule.isEligible(Self.item(8, at: soon, basis: .confirmed), now: now))
        #expect(DetailReminderRule.isEligible(Self.item(8, at: soon, basis: .announced), now: now))
        // An announced day, an estimate, a past row, a row within a minute: no bell.
        #expect(!DetailReminderRule.isEligible(Self.item(8, at: soon, basis: .announced, precision: .day), now: now))
        #expect(!DetailReminderRule.isEligible(Self.item(8, at: soon, basis: .estimated), now: now))
        #expect(!DetailReminderRule.isEligible(Self.item(8, at: soon, basis: .confirmed, isPast: true), now: now))
        #expect(!DetailReminderRule.isEligible(Self.item(8, at: now.addingTimeInterval(30), basis: .confirmed), now: now))
        #expect(!DetailReminderRule.isEligible(Self.item(8, at: nil, basis: .confirmed), now: now))
        // Only titles the reminder plan follows (watching / rewatching).
        let row = Self.item(8, at: soon, basis: .confirmed)
        #expect(DetailReminderRule.showsBell(row, status: .current, now: now))
        #expect(DetailReminderRule.showsBell(row, status: .repeating, now: now))
        #expect(!DetailReminderRule.showsBell(row, status: .planning, now: now))
        #expect(!DetailReminderRule.showsBell(row, status: nil, now: now))
    }

    @Test("Bell labels and toasts EN/DE (§11.4, §15)")
    func bellCopy() {
        let ep = Self.item(8, at: Date(), basis: .confirmed)
        #expect(DetailReminderRule.label(ep, isOn: false, german: false) == "Remind me when episode 8 airs")
        #expect(DetailReminderRule.label(ep, isOn: true, german: true) == "Erinnerung für Folge 8 an")
        let ch = Self.item(68, kind: .chapter, at: Date(), basis: .confirmed)
        #expect(DetailReminderRule.label(ch, isOn: false, german: false) == "Remind me when chapter 68 is out")
        #expect(DetailReminderRule.label(ch, isOn: false, german: true) == "Erinnere mich, wenn Kapitel 68 erscheint")
        #expect(DetailReminderRule.toast(.on, german: false) == "Reminder on. Kuro tells you when it's out.")
        #expect(DetailReminderRule.toast(.off, german: true) == "Erinnerung aus.")
        #expect(DetailReminderRule.toast(.denied, german: false) == "Notifications are off for Kuro. Turn them on in Settings.")
        #expect(DetailReminderRule.toast(.failed, german: true) == "Erinnerung konnte nicht gesetzt werden.")
        #expect(DetailNextRelease.estimateNote(german: false) == "Estimates don't send reminders.")
    }

    // MARK: §6.2 Season tab

    @Test("Season tab: a proven chain with two or more numbered seasons, on a numbered season")
    func seasonTab() {
        func season(_ id: Int, _ number: Int?, current: Bool) -> LadderSeason {
            LadderSeason(entry: LadderChainEntry(mediaId: id, title: "S\(id)", format: "TV"), number: number,
                         partLabel: nil, isCurrent: current)
        }
        let two = [season(1, 1, current: false), season(2, 2, current: true)]
        #expect(DetailSeasonTabRule.tab(chainIsProven: true, numbered: two).map { [$0.number, $0.of] } == [2, 2])
        #expect(DetailSeasonTabRule.tab(chainIsProven: false, numbered: two) == nil)
        #expect(DetailSeasonTabRule.tab(chainIsProven: true, numbered: [season(1, 1, current: true)]) == nil)
        #expect(DetailSeasonTabRule.spoken(2, of: 3, german: false) == "Season 2 of 3. Shows all seasons.")
        #expect(DetailSeasonTabRule.spoken(2, of: 3, german: true) == "Staffel 2 von 3. Zeigt alle Staffeln.")
        #expect(DetailSeasonTabRule.of(3, german: true) == "von 3")
    }

    // MARK: §6.4.3 EpisodeStillPolicy (D20)

    @Test("Stills guard: JJK S2 rejected, Apothecary offset 24, a clean season accepted")
    func stillPolicy() {
        // JJK S2 (145064): AniList attached Season 1's 24 episodes to a 23-episode season.
        #expect(EpisodeStillPolicy.verdict(numbers: Array(1...24), total: 23, priorEpisodes: nil)
                == .init(showsSourceRows: false, offset: 0))
        // Only ~10 rows load at a time: a number past the total is the same signal.
        #expect(!EpisodeStillPolicy.verdict(numbers: Array(15...24), total: 23, priorEpisodes: nil).showsSourceRows)
        // Apothecary S1 (161645): absolute numbering 25–48 after 24 earlier episodes.
        #expect(EpisodeStillPolicy.verdict(numbers: Array(25...48), total: 24, priorEpisodes: 24)
                == .init(showsSourceRows: true, offset: 24))
        // Without the earlier seasons' total the offset is unknown: rejected, never guessed.
        #expect(!EpisodeStillPolicy.verdict(numbers: Array(25...48), total: 24, priorEpisodes: nil).showsSourceRows)
        #expect(EpisodeStillPolicy.verdict(numbers: Array(1...12), total: 12, priorEpisodes: nil)
                == .init(showsSourceRows: true, offset: 0))
        // Unknown total: accepted when the list starts at 1.
        #expect(EpisodeStillPolicy.verdict(numbers: [1, 2, 3], total: nil, priorEpisodes: nil).showsSourceRows)
        #expect(!EpisodeStillPolicy.verdict(numbers: [13, 14], total: nil, priorEpisodes: nil).showsSourceRows)
        #expect(EpisodeStillPolicy.verdict(numbers: [], total: 12, priorEpisodes: nil).showsSourceRows)
        // The live page loads ~10 rows: rows 5–14 look clean, the probe past the total rejects them.
        #expect(EpisodeStillPolicy.verdict(numbers: Array(5...14), total: 23, priorEpisodes: nil).showsSourceRows)
        #expect(!EpisodeStillPolicy.verdict(numbers: Array(5...14), total: 23, priorEpisodes: nil,
                                            sourceExceedsTotal: true).showsSourceRows)
        #expect(EpisodeStillPolicy.verdict(numbers: Array(5...14), total: 23, priorEpisodes: nil,
                                           sourceExceedsTotal: false).showsSourceRows)
    }

    @Test("Timeline: an open watched run draws at most 50 rows, the earlier ones as one line")
    func runCap() {
        let short = DetailTimeline.runRows(1...4)
        #expect(short.earlier == nil && short.shown == [1, 2, 3, 4])
        let long = DetailTimeline.runRows(1...1_098)
        #expect(long.shown.count == 50)
        #expect(long.shown.first == 1_049 && long.shown.last == 1_098)
        #expect(long.earlier == 1...1_048)
    }

    @Test("Facts line: 9 pt in a 320 pt phone's hero column, 10 pt otherwise")
    func factsSize() {
        #expect(DetailFactsLine.size(width: 272) == 9)
        #expect(DetailFactsLine.size(width: 342) == 10)
        #expect(DetailFactsLine.size(width: 0) == 10)
    }

    // MARK: §6.4 Timeline

    @Test("Timeline: watched run, collapsed rows around Up next, future rows without repeats")
    func timelineRows() {
        #expect(DetailTimeline.watchedRun(progress: 6, isTracked: true) == 1...4)
        #expect(DetailTimeline.watchedRun(progress: 2, isTracked: true) == nil)
        #expect(DetailTimeline.watchedRun(progress: 6, isTracked: false) == nil)
        // Tracked at 6, Up next 7, episodes 5–14 loaded: 5, 6, (Up next 7), 8.
        #expect(DetailTimeline.collapsedRows(progress: 6, isTracked: true, upNext: 7, loaded: Array(5...14)) == [5, 6, 8])
        // Caught up (no Up next): the watched rows, then the next loaded one.
        #expect(DetailTimeline.collapsedRows(progress: 12, isTracked: true, upNext: nil, loaded: Array(11...12)) == [11, 12])
        // Untracked: the first three, from Episode 1.
        #expect(DetailTimeline.collapsedRows(progress: 0, isTracked: false, upNext: nil, loaded: [3, 1, 2, 4]) == [1, 2, 3])
        #expect(DetailTimeline.expandedRows(loaded: [3, 1, 2, 2], upNext: 2) == [1, 3])
        let soon = Date().addingTimeInterval(86_400)
        let future = DetailTimeline.futureRows([Self.item(8, at: soon, basis: .confirmed),
                                                Self.item(9, at: soon, basis: .estimated),
                                                Self.item(10, at: soon, basis: .estimated),
                                                Self.item(11, at: soon, basis: .estimated)], drawn: [8])
        #expect(future.compactMap(\.wholeUnitNumber) == [9, 10, 11])
        #expect(DetailTimeline.isWatched(6, progress: 6, isTracked: true))
        #expect(!DetailTimeline.isWatched(7, progress: 6, isTracked: true))
        #expect(!DetailTimeline.isWatched(1, progress: 6, isTracked: false))
    }

    @Test("Timeline copy: generic titles omitted, notes, runs and spoken rows EN/DE")
    func timelineCopy() {
        #expect(DetailTimeline.isGenericTitle("Episode 7"))
        #expect(DetailTimeline.isGenericTitle("folge 7"))
        #expect(DetailTimeline.isGenericTitle("Ep. 12"))
        #expect(DetailTimeline.isGenericTitle("  "))
        #expect(DetailTimeline.isGenericTitle(nil))
        #expect(!DetailTimeline.isGenericTitle("Premature Death"))
        #expect(DetailTimeline.shownTitle(" Premature Death ") == "Premature Death")
        #expect(DetailTimeline.note(progress: 6, total: 23, isTracked: true, german: false) == "6 of 23 watched")
        #expect(DetailTimeline.note(progress: 6, total: 23, isTracked: true, german: true) == "6 von 23 gesehen")
        #expect(DetailTimeline.note(progress: 0, total: 26, isTracked: false, german: false) == "26 episodes")
        #expect(DetailTimeline.note(progress: 0, total: nil, isTracked: false, german: false) == nil)
        #expect(DetailTimeline.smallLine(5, watched: true, german: false) == "Ep. 5 · watched")
        #expect(DetailTimeline.smallLine(5, watched: true, german: true) == "F. 5 · gesehen")
        #expect(DetailTimeline.runLine(1...4, german: false) == "Episodes 1–4 · watched")
        #expect(DetailTimeline.runLine(1...4, manga: true, german: true) == "Kapitel 1–4 · gelesen")
        #expect(DetailTimeline.absoluteNumber(29, german: true) == "Nr. 29")
        #expect(DetailTimeline.spokenRow(number: 5, title: "Premature Death", date: "Friday 17 October", watched: true, german: false)
                == "Episode 5, Premature Death, Friday 17 October, watched")
        #expect(DetailTimeline.spokenRow(number: 5, title: nil, date: nil, watched: false, german: true) == "Folge 5")
    }

    @Test("Timeline air day: a day-only date is read as its UTC calendar day")
    func timelineDay() {
        // 2026-10-17 00:00 UTC (a day-only air date): never "Thu 16 Oct" west of UTC.
        let day = Date(timeIntervalSince1970: 1_792_195_200)
        let newYork = TimeZone(identifier: "America/New_York") ?? .current
        let text = DetailTimeline.dayText(airAt: nil, airDate: day, long: false, locale: Self.en, timeZone: newYork)
        #expect(text?.contains("17") == true)
        #expect(DetailTimeline.dayText(airAt: nil, airDate: nil, long: false, locale: Self.en, timeZone: newYork) == nil)
    }

    // MARK: §6.7 Cast (D8)

    @Test("Cast: main and supporting first in source order, cap 25, background only alone; labels")
    func castRule() {
        let roles = ["SUPPORTING", "BACKGROUND", "MAIN", "SUPPORTING"]
        let shown = DetailCastRule.shown(Array(roles.enumerated()), role: { $0.element })
        #expect(shown.map(\.offset) == [2, 0, 3])
        let many = DetailCastRule.shown(Array(repeating: "MAIN", count: 40), role: { $0 })
        #expect(many.count == 25)
        #expect(DetailCastRule.shown(["BACKGROUND", "BACKGROUND"], role: { $0 }).count == 2)
        #expect(DetailCastRule.shown([String](), role: { $0 }).isEmpty)
        #expect(DetailCastRule.roleWord("MAIN", german: true) == "Hauptrolle")
        #expect(DetailCastRule.roleWord("BACKGROUND", german: false) == "Background")
        #expect(DetailCastRule.note(count: 3, hasVoices: true, german: false) == "Japanese cast")
        #expect(DetailCastRule.note(count: 3, hasVoices: false, german: true) == "3 Figuren")
        #expect(DetailCastRule.note(count: 1, hasVoices: false, german: false) == "1 character")
        #expect(DetailCastRule.spokenCard(name: "Maomao", role: "Main") == "Maomao, Main")
        #expect(DetailCastRule.spokenVoice(name: "Aoi Yuuki", character: "Maomao", german: false) == "Aoi Yuuki, voice of Maomao")
        #expect(DetailCastRule.spokenVoice(name: "Aoi Yuuki", character: "Maomao", german: true) == "Aoi Yuuki, Stimme von Maomao")
    }

    @MainActor
    @Test("Cast rail: the data lane's fixture cast keeps its leads and drops the background soldier")
    func castRailFixture() {
        let shown = DetailCastRail.shown(CatalogVoiceFixtures.cast())
        #expect(shown.count == 3)
        #expect(shown.allSatisfy { $0.voiceActor != nil })
    }

    // MARK: §6.8 More like this (D7)

    @Test("More like this: own ladder and duplicates dropped; card line; account-keyed state")
    func moreLikeThis() {
        let keys = [MediaKey(kind: .anime, id: 1), MediaKey(kind: .anime, id: 2), MediaKey(kind: .anime, id: 2),
                    MediaKey(kind: .manga, id: 1)]
        let kept = DetailMoreLikeThisRule.filtered(keys, key: { $0 }, excluding: [MediaKey(kind: .anime, id: 1)])
        #expect(kept == [MediaKey(kind: .anime, id: 2), MediaKey(kind: .manga, id: 1)])
        #expect(DetailMoreLikeThisRule.cardLine(year: "2019", format: "TV", kind: .anime, german: false) == "2019 · TV")
        #expect(DetailMoreLikeThisRule.cardLine(year: "TBA", format: "MANGA", kind: .manga, german: false) == "Manga")
        #expect(DetailMoreLikeThisRule.cardLine(year: "", format: nil, kind: .anime, german: false) == nil)
        #expect(DetailMoreLikeThisRule.heading(german: true) == "Mehr davon.")
        #expect(DetailMoreLikeThisRule.note(german: false) == "From what this title shares")
        #expect(DetailMoreLikeThisRule.stateKey(account: "A", kind: .anime, id: 7)
                != DetailMoreLikeThisRule.stateKey(account: "B", kind: .anime, id: 7))
    }

    @Test("Sections: More like this sits between the credits and Between us, only with cards")
    func moreLikeThisSection() {
        let without = DetailInput(hasSynopsis: true, creditCount: 1, similarCount: 0)
        #expect(!DetailSectionPolicy.sections(for: without).contains(.moreLikeThis))
        let with = DetailInput(hasSynopsis: true, creditCount: 1, hasClubs: true, socialEnabled: true, similarCount: 4)
        #expect(DetailSectionPolicy.sections(for: with) == [.hero, .story, .credits, .moreLikeThis, .betweenUs])
    }

    // MARK: §5.2 Branded tile

    @Test("Branded tile initials")
    func tileInitials() {
        #expect(KuroBrandedTile.initials("Aoi Yuuki") == "AY")
        #expect(KuroBrandedTile.initials("MAPPA") == "MA", "folded tile: one word gives two letters")
        #expect(KuroBrandedTile.initials("  ") == nil)
        #expect(KuroBrandedTile.initials(nil) == nil)
    }
}
