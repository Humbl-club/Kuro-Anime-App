//
//  HomeMangaLaneTests.swift
//  KuroTests
//
//  Prototype-fidelity Task 5 (Home: manga leaves, calendar card, club room, footer). Pure rules for
//  the leaf geometry, the calendar card's copy and paging, and the club room's honesty rules, plus
//  fixture renders of the components composed in Home order (evidence for the fidelity review).
//

import Foundation
import KuroCore
import SwiftUI
import Testing
import UIKit
@testable import Kuro

@MainActor
@Suite("Home manga lane: leaves, calendar card, club room")
struct HomeMangaLaneTests {
    // Wed 14 Oct 2026, 12:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_979_200)

    static func copy(german: Bool) throws -> ReleaseCopy {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        return ReleaseCopy(now: now, german: german, locale: Locale(identifier: german ? "de_DE" : "en_GB"),
                           timeZone: berlin)
    }

    static func row(_ id: Int, _ at: Date?, medium: MediaKind = .manga, unit: ReleaseUnitKind = .chapter,
                    basis: ReleaseBasis = .confirmed, precision: ReleasePrecision? = nil) -> ReleaseScheduleItem {
        ReleaseScheduleItem(medium: medium, mediaId: id, title: "T\(id)", unitKind: unit, unitNumber: Double(id),
                            releaseAt: at, basis: basis, source: "anilist", precision: precision)
    }

    // MARK: Manga leaves

    @Test("manga leaves are three columns with Ch + key row")
    func leavesAreThreeColumns() {
        let regular = HomeMangaLeafMetrics(width: 346) // 390 pt phone, 22 pt gutters
        #expect(regular.columns == 3)
        #expect(regular.columnWidth == 106)
        #expect(regular.columnGap == 14 && regular.rowGap == 26)
        #expect(regular.coverHeight == 138)

        let small = HomeMangaLeafMetrics(width: 286) // 320 pt phone, 17 pt gutters
        #expect(small.columns == 3)
        #expect(small.columnWidth == 88)
        #expect(small.columnGap == 11 && small.rowGap == 24)
        #expect(small.coverHeight == 119)

        let large = HomeMangaLeafMetrics(width: 386) // 430 pt phone: wider leaves, same cover height
        #expect(large.columns == 3)
        #expect(large.columnWidth > regular.columnWidth)
        #expect(large.coverHeight == 138)

        // The Ch. + key row: the key keeps its own 44 pt column and the count has room beside it.
        for metrics in [regular, small, large] {
            #expect(HomeMangaLeafMetrics.keyColumn == 44)
            #expect(metrics.readoutWidth >= 40, "the count keeps room beside the key at \(metrics.columnWidth)")
        }
        // The row's label: "Ch." over the count, or the caught-up word (EN/DE).
        #expect(HomeMangaLeafMetrics.readoutLabel(caughtUp: false, german: false) == "Ch.")
        #expect(HomeMangaLeafMetrics.readoutLabel(caughtUp: false, german: true) == "Kap.")
        #expect(HomeMangaLeafMetrics.readoutLabel(caughtUp: true, german: false) == "Caught up")
        #expect(HomeMangaLeafMetrics.readoutLabel(caughtUp: true, german: true) == "Auf dem neuesten Stand")
        // The loading leaves take the real leaf's height (cover, gap, title box, row).
        #expect(regular.leafHeight == 240) // 138 + 8 + 44 + 50
        #expect(small.leafHeight == 219) // 119 + 6 + 44 + 50
    }

    @Test("A releasing manga reached its released chapter: the leaf is caught up (no +1 for an unreleased chapter)")
    func mangaLeafKeyHasAReleaseCeiling() {
        // RELEASING, no catalogue total, the schedule's next (non-estimated) chapter is 115, read 114.
        let row = ReleaseScheduleItem(medium: .manga, mediaId: 7, title: "T7", unitKind: .chapter, unitNumber: 115,
                                      releaseAt: Self.now.addingTimeInterval(86_400), basis: .announced,
                                      source: "mangaupdates", precision: .day)
        let next = HomeShelfPolicy.nextUnitNumber([row], medium: .manga)
        let available = HomeShelfPolicy.availableUnits(catalogueStatus: "RELEASING", total: nil, nextUnit: next)
        #expect(available == 114)
        #expect(HomeShelfPolicy.homeKeyCaughtUp(progress: 114, total: nil, available: available))
        #expect(!HomeShelfPolicy.homeKeyCaughtUp(progress: 113, total: nil, available: available))
        // No schedule: the released count is unknown, so the key stays a +1 (never a guessed ✓).
        let unknown = HomeShelfPolicy.availableUnits(catalogueStatus: "RELEASING", total: nil, nextUnit: nil)
        #expect(!HomeShelfPolicy.homeKeyCaughtUp(progress: 114, total: nil, available: unknown))
        // The opening line agrees: nothing new.
        let opening = HomeShelfPolicy.opening([.init(progress: 114, available: available, catalogueStatus: "RELEASING")])
        #expect(opening.newUnits == 0 && opening.nothingNew)
        // The leaf's readout: "Caught up" in the "Ch." slot over the count (EN); German the long word
        // takes the count's lines (LANE_AMENDMENTS 14).
        #expect(HomeMangaLeafMetrics.readoutLabel(caughtUp: true, german: true) == "Auf dem neuesten Stand")
        #expect(HomeMangaLeafMetrics.showsCount(caughtUp: true, german: false))
        #expect(!HomeMangaLeafMetrics.showsCount(caughtUp: true, german: true))
        #expect(HomeMangaLeafMetrics.showsCount(caughtUp: false, german: true))
    }

    // MARK: Calendar card

    @Test("calendar day chip shows day number and month abbreviation (EN \"OCT\", DE \"OKT\")")
    func calendarChip() throws {
        let day = DateComponents(year: 2026, month: 10, day: 2)
        let en = try Self.copy(german: false)
        let de = try Self.copy(german: true)
        let enHeading = try #require(en.dayHeading(day))
        let deHeading = try #require(de.dayHeading(day))
        #expect(enHeading.day == "2")
        #expect(deHeading.day == "2")
        #expect(HomeCalendarPresentation.chipMonth(enHeading.month, locale: en.locale) == "OCT")
        #expect(HomeCalendarPresentation.chipMonth(deHeading.month, locale: de.locale) == "OKT")
        #expect(HomeCalendarPresentation.chipMonth("Mai", locale: de.locale) == "MAI")
    }

    @Test("Dates to come row appears only for announced/undated items")
    func datesToComeOnlyWhenUndated() throws {
        let copy = try Self.copy(german: false)
        let dated = [Self.row(1, Self.now.addingTimeInterval(3_600)),
                     Self.row(2, Self.now.addingTimeInterval(86_400 + 3_600))]
        let datedGroups = HomeCalendarPresentation.groups(dated, copy: copy)
        #expect(!datedGroups.contains { $0.kind == .undated })
        #expect(HomeCalendarPresentation.paged(datedGroups, showAll: false).undated == nil)

        let withUndated = dated + [Self.row(3, nil, basis: .announced), Self.row(4, nil, basis: .announced)]
        let groups = HomeCalendarPresentation.groups(withUndated, copy: copy)
        let last = try #require(groups.last)
        #expect(last.kind == .undated)
        #expect(last.label == "Dates to come")
        #expect(last.items.map(\.mediaId) == [3, 4])
        #expect(HomeCalendarPresentation.paged(groups, showAll: false).undated?.id == last.id)
        #expect(HomeCalendarPresentation.announcementCount(2, german: false) == "2 announcements")
        #expect(HomeCalendarPresentation.announcementCount(1, german: true) == "1 Ankündigung")

        // Only undated rows: "From your list", never a release count.
        let undatedOnly = HomeCalendarPresentation.groups([Self.row(5, nil, basis: .announced)], copy: copy)
        #expect(HomeCalendarPresentation.summary(undatedOnly, coverage: .complete, copy: copy) == "From your list")
    }

    @Test("Calendar summary counts dated releases and the span they cover (EN/DE)")
    func calendarSummary() throws {
        let en = try Self.copy(german: false)
        let de = try Self.copy(german: true)
        let week = (0..<6).map { Self.row($0 + 1, Self.now.addingTimeInterval(Double($0) * 86_400 + 3_600)) }
        let groups = HomeCalendarPresentation.groups(week, copy: en)
        #expect(HomeCalendarPresentation.summary(groups, coverage: .complete, copy: en) == "6 releases · 7 days")
        #expect(HomeCalendarPresentation.summary(HomeCalendarPresentation.groups(week, copy: de),
                                                 coverage: .complete, copy: de) == "6 Veröffentlichungen · 7 Tage")
        let far = week + [Self.row(40, Self.now.addingTimeInterval(38 * 86_400))]
        #expect(HomeCalendarPresentation.summary(HomeCalendarPresentation.groups(far, copy: en),
                                                 coverage: .complete, copy: en) == "7 releases · 6 weeks")
        #expect(HomeCalendarPresentation.summary(groups, coverage: .nextSevenDays, copy: en) == "6 releases · 7 days")
        let daySeven = HomeCalendarPresentation.groups([Self.row(1, Self.now.addingTimeInterval(7 * 86_400))], copy: en)
        #expect(HomeCalendarPresentation.summary(daySeven, coverage: .complete, copy: en) == "1 release · 7 days")
        let dayEight = HomeCalendarPresentation.groups([Self.row(1, Self.now.addingTimeInterval(8 * 86_400))], copy: en)
        #expect(HomeCalendarPresentation.summary(dayEight, coverage: .complete, copy: en) == "1 release · 2 weeks")
    }

    @Test("Calendar rows say their own certainty: time, kind of release, TBA, expected")
    func calendarRowWhen() throws {
        let en = try Self.copy(german: false)
        let de = try Self.copy(german: true)
        // 16:00 Berlin on 14 Oct = 14:00 UTC.
        let exact = Self.row(1, Self.now.addingTimeInterval(2 * 3_600), medium: .anime, unit: .episode)
        #expect(HomeCalendarPresentation.rowWhen(exact, copy: en) == "16:00")
        #expect(HomeCalendarPresentation.rowWhen(exact, copy: de) == "16:00")
        let dayChapter = Self.row(2, Date(timeIntervalSince1970: 1_792_022_400), basis: .announced, precision: .day)
        #expect(HomeCalendarPresentation.rowWhen(dayChapter, copy: en) == "Chapter release")
        #expect(HomeCalendarPresentation.rowWhen(dayChapter, copy: de) == "Neues Kapitel")
        let dayVolume = Self.row(3, Date(timeIntervalSince1970: 1_792_022_400), unit: .volume, basis: .announced, precision: .day)
        #expect(HomeCalendarPresentation.rowWhen(dayVolume, copy: en) == "Volume release", "never claims an English edition")
        let dayEpisode = Self.row(4, Date(timeIntervalSince1970: 1_792_022_400), medium: .anime, unit: .episode,
                                  basis: .announced, precision: .day)
        #expect(HomeCalendarPresentation.rowWhen(dayEpisode, copy: en) == "Time TBA")
        let undated = Self.row(5, nil, basis: .announced)
        #expect(HomeCalendarPresentation.rowWhen(undated, copy: en) == "Date TBA")
        #expect(HomeCalendarPresentation.rowWhen(undated, copy: de) == "Datum offen")
        let estimated = Self.row(6, Self.now.addingTimeInterval(86_400), basis: .estimated)
        #expect(HomeCalendarPresentation.rowWhen(estimated, copy: en) == "Expected")
    }

    @Test("Calendar state is kept per medium; the skeleton shows only while the schedule is asked")
    func calendarStateAndLoading() throws {
        #expect(HomeCalendarCard.stateKey(manga: true, dayId: "2026-11-01") == "manga|2026-11-01")
        #expect(HomeCalendarCard.stateKey(manga: false, dayId: "2026-11-01") == "anime|2026-11-01")
        #expect(HomeCalendarCard.showsLoading(groups: [], coverage: .pending))
        #expect(!HomeCalendarCard.showsLoading(groups: [], coverage: .complete), "an answered empty schedule is not loading")
        #expect(!HomeCalendarCard.showsLoading(groups: [], coverage: .noSource))
        let copy = try Self.copy(german: false)
        let groups = HomeCalendarPresentation.groups([Self.row(1, Self.now.addingTimeInterval(3_600))], copy: copy)
        #expect(!HomeCalendarCard.showsLoading(groups: groups, coverage: .pending))
        // Manga stamps are square but for the top-right corner; anime are round all over.
        #expect(HomeCalendarPalette.manga.chipCorners.topTrailing == 10 && HomeCalendarPalette.manga.chipCorners.topLeading == 4)
        #expect(HomeCalendarPalette.manga.artRadius == 1 && HomeCalendarPalette.manga.eventsBottomRadius == 8)
        #expect(HomeCalendarPalette.anime.chipCorners.bottomLeading == 10 && HomeCalendarPalette.anime.artRadius == 3)
    }

    @Test("Calendar pages after four dated groups; Dates to come stays visible")
    func calendarPaging() throws {
        let copy = try Self.copy(german: false)
        let rows = (0..<6).map { Self.row($0 + 1, Self.now.addingTimeInterval(Double($0) * 86_400 + 3_600)) }
            + [Self.row(9, nil, basis: .announced)]
        let groups = HomeCalendarPresentation.groups(rows, copy: copy)
        let paged = HomeCalendarPresentation.paged(groups, showAll: false)
        #expect(paged.visible.count == 4)
        #expect(paged.hidden.count == 2)
        #expect(paged.undated != nil)
        let all = HomeCalendarPresentation.paged(groups, showAll: true)
        #expect(all.visible.count == 6 && all.hidden.isEmpty && all.undated != nil)
    }

    // MARK: Club room

    static func club(_ id: String, name: String = "Club", at: TimeInterval?, members: [String] = [],
                     archived: Bool = false, preview: String? = nil) -> ClubListRow {
        let iso = ISO8601DateFormatter()
        return ClubListRow(id: id, name: name, sharing_level: "status", is_archived: archived,
                           created_at: "2026-01-01T00:00:00Z", member_count: members.count, rail_count: 1,
                           poll_count: 0, last_activity_at: at.map { iso.string(from: now.addingTimeInterval($0)) },
                           activity_preview: preview, cover_images: ["https://example.invalid/a.jpg"],
                           member_names: members, loading_state: nil)
    }

    static func note(_ id: String, by name: String?, text: String?, scope: String = "none",
                     ago: TimeInterval = 3_600) -> HomeClubItem {
        HomeClubItem(commentId: id, mediaId: 7, mediaType: "manga", spoilerScope: scope, text: text,
                     displayName: name, createdAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-ago)))
    }

    @Test("club room picks the most recent activity, hides with no clubs")
    func clubRoomPick() throws {
        #expect(HomeClubRoom.pick(clubs: []) == nil)
        let quiet = try #require(ClubSummary(row: Self.club("q", at: nil)))
        #expect(HomeClubRoom.pick(clubs: [quiet]) == nil, "a club without real activity does not open the room")
        let older = try #require(ClubSummary(row: Self.club("a", at: -7_200)))
        let newer = try #require(ClubSummary(row: Self.club("b", at: -600)))
        #expect(HomeClubRoom.pick(clubs: [older, quiet, newer])?.id == "b")
        #expect(HomeClubRoom.pick(clubs: [newer, older])?.id == "b")
    }

    @Test("club room never shows a fabricated club name")
    func clubRoomNeverFabricates() throws {
        #expect(ClubSummary(row: Self.club("x", name: "   ", at: -60)) == nil, "no blank name and no stand-in")
        #expect(ClubSummary(row: Self.club("y", name: "Sunday Club", at: -60, archived: true)) == nil)
        let real = try #require(ClubSummary(row: Self.club("z", name: "  Sunday Club ", at: -60)))
        #expect(real.name == "Sunday Club")

        // With several clubs the slice cannot say which club a note came from: no note is shown.
        let club = try #require(ClubSummary(row: Self.club("z", name: "Sunday Club", at: -60, members: ["Mina", "Jules"])))
        let items = [Self.note("1", by: "Noah", text: "Elsewhere."),
                     Self.note("2", by: "mina", text: "Here.", ago: 60),
                     Self.note("3", by: nil, text: "Unknown author.")]
        #expect(HomeClubRoom.roomNotes(items, club: club, clubCount: 2).isEmpty)
        // Two clubs that both have an "Alex": Alex's note from the other club never lands here.
        let alexHere = try #require(ClubSummary(row: Self.club("a", name: "Sunday Club", at: -60, members: ["Alex", "Mina"])))
        let fromOtherClub = [Self.note("9", by: "Alex", text: "Said in the other club.")]
        #expect(HomeClubRoom.roomNotes(fromOtherClub, club: alexHere, clubCount: 2).isEmpty)
        #expect(HomeClubRoom.roomNotes(fromOtherClub, club: alexHere, clubCount: 5).isEmpty)
        // With one club every note is from one of its members (they share only this club).
        #expect(HomeClubRoom.roomNotes(items, club: club, clubCount: 1).map(\.commentId) == ["2", "1", "3"])

        // Spoiler notes never carry text into Home and read from their real scope.
        let spoiler = HomeClubRoom.Note(item: Self.note("4", by: "Mina", text: "the twist", scope: "ending"),
                                        title: "Berserk", coverImage: nil)
        #expect(spoiler.text == nil && spoiler.isSpoiler)
        #expect(HomeClubRoom.spoilerLine(author: "Mina", scope: "ending", german: false) == "Mina’s thought on the ending")
        #expect(HomeClubRoom.spoilerLine(author: "Mina", scope: "story", german: true) == "Minas Gedanke zur Geschichte")
        #expect(HomeClubRoom.spoilerLine(author: "Jonas", scope: "ending", german: true) == "Jonas’ Gedanke zum Ende")

        // The activity line is the server's own preview; anything else shows nothing.
        #expect(HomeClubRoom.activity(from: "Added: Solo Leveling") == .init(kind: .added, subject: "Solo Leveling"))
        #expect(HomeClubRoom.activity(from: "Poll: Next pick?") == .init(kind: .poll, subject: "Next pick?"))
        #expect(HomeClubRoom.activity(from: "Something else") == nil)
        #expect(HomeClubRoom.activity(from: nil) == nil)
        #expect(HomeClubRoom.updateCount(notes: [spoiler], activity: nil) == 1)

        // A spoiler joins the lead card only when the same person wrote it on the same title.
        let lead = HomeClubRoom.Note(item: Self.note("5", by: "Mina", text: "Just one more."), title: "Berserk", coverImage: nil)
        let other = HomeClubRoom.Note(item: Self.note("6", by: "Jules", text: nil, scope: "ending"), title: "Berserk", coverImage: nil)
        let paired = HomeClubRoom.layout([lead, other, spoiler])
        #expect(paired.lead?.id == "5" && paired.leadSpoiler?.id == "4" && paired.rows.map(\.id) == ["6"])
        let unpaired = HomeClubRoom.layout([lead, other])
        #expect(unpaired.leadSpoiler == nil && unpaired.rows.map(\.id) == ["6"])
        #expect(HomeClubRoom.updateCount(notes: [lead, other, spoiler], activity: .init(kind: .added, subject: "X")) == 3)
        #expect(HomeClubRoom.timeAgo(Self.now.addingTimeInterval(-7_200), now: Self.now, german: false) == "2h ago")
        #expect(HomeClubRoom.timeAgo(Self.now.addingTimeInterval(-7_200), now: Self.now, german: true) == "vor 2 Std.")
        #expect(HomeClubRoom.timeAgo(nil, now: Self.now, german: false) == nil)
        #expect(HomeClubRoom.initials(["mina", "Jules", "Ari", "Noah"]) == ["M", "J", "A"])
        // A failed clubs read with no known club is a failure, never "no clubs"; a known club keeps its room.
        #expect(HomeClubRoom.presentation(picked: nil, clubsReadFailed: false, notesFailed: false) == .hidden)
        #expect(HomeClubRoom.presentation(picked: nil, clubsReadFailed: true, notesFailed: false) == .failed)
        #expect(HomeClubRoom.presentation(picked: real, clubsReadFailed: true, notesFailed: true)
                == .room(real, notesFailed: true))
        // A transport failure reads as offline, never as "Couldn't load".
        #expect(HomeClubRoom.presentation(picked: nil, clubsReadFailed: true, notesFailed: false, offline: true) == .offline)
        #expect(HomeClubRoom.presentation(picked: nil, clubsReadFailed: false, notesFailed: false, offline: true) == .hidden)
        #expect(HomeClubRoom.presentation(picked: real, clubsReadFailed: true, notesFailed: false, offline: true)
                == .room(real, notesFailed: false))
        let offlineCopy = HomeClubRoomFailureLine.copy(.offline, german: false)
        #expect(offlineCopy.headline == "You're offline." && offlineCopy.message == "Connect to load this.")
        #expect(HomeClubRoomFailureLine.copy(.offline, german: true).headline == "Du bist offline.")
        let failedCopy = HomeClubRoomFailureLine.copy(.failed(headline: "Couldn't load your clubs."), german: false)
        #expect(failedCopy.headline == "Couldn't load your clubs." && failedCopy.message == "Try again in a moment.")
        #expect(HomeClubRoom.memberFills.count == 3)
        // The small-phone room (≈ 296 pt at 320) and the regular one (356 pt at 390).
        #expect(HomeClubRoom.isCompact(width: 296) && !HomeClubRoom.isCompact(width: 356))
    }
}

// MARK: - Layout policy (plan edge case 1)

@MainActor
@Suite("Home layout policy", .serialized)
struct HomeLayoutPolicyTests {
    private static let longTitle = "Die sehr lange Geschichte eines wandernden Schwertes"

    /// The hosted height of the view at `width`, at the given text size (the app scale and the
    /// environment), restored before returning; nothing awaits in between. The view is built inside
    /// the scaled window, so fonts made by `kuroCustom` read the scaled size.
    private static func height<V: View>(width: CGFloat, size: DynamicTypeSize, _ make: () -> V) -> CGFloat {
        let saved = KuroTypeScale.current.category
        KuroTypeScale.current.update(size)
        defer { KuroTypeScale.current.update(category: saved ?? .large) }
        let host = UIHostingController(rootView: make().environment(\.dynamicTypeSize, size).frame(width: width))
        return host.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
    }

    private static func card(_ title: String) -> HomeCard {
        HomeCard(mediaId: 1, listType: "current", progress: 24, progressLabel: nil, volumesProgress: nil,
                 serverRevision: 1, lifecycleId: "fixture", unitId: nil, title: title, bannerImage: nil,
                 coverImage: nil, format: "MANGA", episodes: nil, chapters: nil, volumes: nil,
                 catalogueStatus: "RELEASING", seriesId: nil, sectionOrdinal: nil, sectionKind: nil,
                 sectionName: nil, material: nil)
    }

    private static func leaf(_ title: String, width: CGFloat) -> some View {
        HomeMangaLeaves(cards: [card(title)], containerWidth: width,
                        readout: { _ in .init(label: "24", caughtUp: false, spoken: "Chapter 24") },
                        onOpen: { _ in }) { _ in Color.black.frame(width: 38, height: 38) }
    }

    @Test("longTitleNeverOverlapsKey: titles wrap to two lines then truncate; the key keeps its 44 pt column")
    func longTitleNeverOverlapsKey() {
        #expect(HomeMangaLeafMetrics.titleLineLimit == 2)
        #expect(HomeMangaLeafMetrics.keyColumn == 44 && HomeMangaLeafMetrics.titleBox == 44)
        for width: CGFloat in [286, 346] {
            let metrics = HomeMangaLeafMetrics(width: width)
            #expect(metrics.readoutWidth >= 40, "the count keeps room beside the key at \(width)")
            for size: DynamicTypeSize in [.large, .accessibility5] {
                let one = Self.height(width: metrics.columnWidth, size: size) {
                    Text("A").font(HomeMangaLeafTitle.font(metrics)).tracking(-0.2).lineLimit(1)
                }
                let short = Self.height(width: metrics.columnWidth, size: size) {
                    HomeMangaLeafTitle(title: "Berserk", metrics: metrics)
                }
                let long = Self.height(width: metrics.columnWidth, size: size) {
                    HomeMangaLeafTitle(title: Self.longTitle, metrics: metrics)
                }
                // Two lines are reserved and used (a short title is not cut to one line in the grid)…
                #expect(long >= one * 1.8, "the long title wraps to two lines at \(size), \(width): one \(one) long \(long)")
                // …and never more than two: short and long titles take the same box.
                #expect(abs(long - short) < 0.5, "titles take the same two-line box at \(size), \(width)")
                #expect(long < one * 2 + 8 + 1 || long <= HomeMangaLeafMetrics.titleBox + 0.5,
                        "the title stops at two lines at \(size), \(width): one \(one) short \(short) long \(long)")
                // Whole leaves line up: the rule and the Ch. + key row start at the same height.
                let shortLeaf = Self.height(width: width, size: size) { Self.leaf("Berserk", width: width) }
                let longLeaf = Self.height(width: width, size: size) { Self.leaf(Self.longTitle, width: width) }
                #expect(abs(shortLeaf - longLeaf) < 0.5, "leaves are level at \(size), \(width)")
                // The key row sits below the title: the leaf is at least cover + title + key column.
                #expect(longLeaf >= metrics.coverHeight + long + HomeMangaLeafMetrics.keyColumn)
            }
        }
    }
}

// MARK: - Fixture renders (evidence; PNGs only with TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1)

@Suite("Home manga lane snapshots", .serialized, .timeLimit(.minutes(3)))
@MainActor
struct HomeMangaLaneSnapshotTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-home-manga", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/prototype-fidelity/native/home-manga")
    }()

    private static let artFiles = ["manga0.jpg", "manga1.jpg", "manga2.jpg", "manga3.jpg",
                                   "journal-manga-13-cover.jpg", "journal-manga-16-cover.jpg",
                                   "anime0.jpg", "anime1.jpg", "anime2.jpg", "anime3.jpg"]

    private static func art(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    private static func seedArtwork() {
        for file in artFiles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)),
                  let url = URL(string: art(file)),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "image/jpeg"]) else { continue }
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                for: URLRequest(url: url))
        }
    }

    // MARK: Fixtures (test data only; never shipped)

    /// Today at 09:00 local time, so the day's releases are all still ahead whenever the suite runs.
    private static let now: Date = {
        let calendar = KuroLocale.calendar
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }()

    private static func card(_ id: Int, _ title: String, _ file: String, progress: Int) -> HomeCard {
        HomeCard(mediaId: id, listType: "current", progress: progress, progressLabel: nil, volumesProgress: nil,
                 serverRevision: 1, lifecycleId: UUID().uuidString, unitId: nil, title: title, bannerImage: nil,
                 coverImage: art(file), format: "MANGA", episodes: nil, chapters: nil, volumes: nil,
                 catalogueStatus: "RELEASING", seriesId: nil, sectionOrdinal: nil, sectionKind: nil,
                 sectionName: nil, material: nil)
    }

    private static let mangaCards: [HomeCard] = [
        card(1, "Chainsaw Man", "manga0.jpg", progress: 24),
        card(2, "Solo Leveling", "manga1.jpg", progress: 8),
        card(3, "Jujutsu Kaisen", "manga2.jpg", progress: 16),
        card(4, "Berserk", "manga3.jpg", progress: 12),
        card(5, "SPY x FAMILY", "journal-manga-13-cover.jpg", progress: 5),
        card(6, "Die sehr lange Geschichte eines wandernden Schwertes", "journal-manga-16-cover.jpg", progress: 40)
    ]

    /// Today at `hour`:00 local time, `days` ahead.
    private static func at(days: Int, hour: Int) -> Date {
        let calendar = KuroLocale.calendar
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return calendar.date(byAdding: .hour, value: hour, to: day) ?? day
    }

    /// A day-precision row stored at 00:00 UTC of the local day `days` ahead (how announced days are stored).
    private static func dayRow(days: Int) -> Date {
        let local = KuroLocale.calendar.dateComponents([.year, .month, .day], from: at(days: days, hour: 12))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? utc.timeZone
        return utc.date(from: local) ?? now
    }

    private static func release(_ id: Int, _ title: String, _ file: String, medium: MediaKind, unit: ReleaseUnitKind,
                                number: Double, at date: Date?, basis: ReleaseBasis,
                                precision: ReleasePrecision?) -> ReleaseScheduleItem {
        ReleaseScheduleItem(medium: medium, mediaId: id, title: title, coverImage: art(file), unitKind: unit,
                            unitNumber: number, releaseAt: date, basis: basis, source: "anilist", precision: precision)
    }

    private static var mangaSchedule: [ReleaseScheduleItem] {
        [
            release(1, "Chainsaw Man", "manga0.jpg", medium: .manga, unit: .chapter, number: 26,
                    at: dayRow(days: 0), basis: .announced, precision: .day),
            release(2, "Solo Leveling", "manga1.jpg", medium: .manga, unit: .volume, number: 11,
                    at: dayRow(days: 0), basis: .announced, precision: .day),
            release(3, "Jujutsu Kaisen", "manga2.jpg", medium: .manga, unit: .chapter, number: 22,
                    at: dayRow(days: 0), basis: .announced, precision: .day),
            release(4, "Berserk", "manga3.jpg", medium: .manga, unit: .chapter, number: 380,
                    at: dayRow(days: 1), basis: .announced, precision: .day),
            release(5, "SPY x FAMILY", "journal-manga-13-cover.jpg", medium: .manga, unit: .chapter, number: 112,
                    at: dayRow(days: 1), basis: .announced, precision: .day),
            release(6, "Vagabond", "journal-manga-16-cover.jpg", medium: .manga, unit: .chapter, number: 328,
                    at: dayRow(days: 7), basis: .announced, precision: .day),
            release(4, "Berserk", "manga3.jpg", medium: .manga, unit: .volume, number: 43,
                    at: nil, basis: .announced, precision: nil),
            release(5, "SPY x FAMILY", "journal-manga-13-cover.jpg", medium: .manga, unit: .volume, number: 15,
                    at: nil, basis: .announced, precision: nil),
            release(6, "Vagabond", "journal-manga-16-cover.jpg", medium: .manga, unit: .volume, number: 38,
                    at: nil, basis: .announced, precision: nil)
        ]
    }

    private static var animeSchedule: [ReleaseScheduleItem] {
        let titles = [("Demon Slayer", "anime1.jpg", 6.0), ("Attack on Titan", "anime0.jpg", 9.0),
                      ("Jujutsu Kaisen", "anime2.jpg", 10.0), ("Mob Psycho 100", "anime3.jpg", 4.0),
                      ("Death Note", "anime0.jpg", 12.0), ("Fullmetal Alchemist", "anime1.jpg", 20.0)]
        var rows: [ReleaseScheduleItem] = []
        for day in [0, 1, 4, 7, 9, 12] {
            for (index, entry) in titles.enumerated() {
                rows.append(release(100 + index, entry.0, entry.1, medium: .anime, unit: .episode,
                                    number: entry.2 + Double(day), at: at(days: day, hour: 16 + min(index, 5)),
                                    basis: .confirmed, precision: .instant))
            }
        }
        rows.append(release(120, "Death Note", "anime0.jpg", medium: .anime, unit: .season, number: 2,
                            at: nil, basis: .announced, precision: nil))
        rows.append(release(121, "Mob Psycho 100", "anime3.jpg", medium: .anime, unit: .season, number: 4,
                            at: nil, basis: .announced, precision: nil))
        rows.append(release(122, "Fullmetal Alchemist", "anime1.jpg", medium: .anime, unit: .season, number: 2,
                            at: nil, basis: .announced, precision: nil))
        return rows
    }

    private static let sundayClub = ClubSummary(
        id: "fixture-club", name: "Sunday Club", lastActivityAt: now.addingTimeInterval(-7_200),
        memberNames: ["Mina", "Jules", "Ari"], memberCount: 3,
        activityPreview: "Added: Solo Leveling", latestCover: art("manga1.jpg"))

    private static func roomNotes(_ medium: MediaKind) -> [HomeClubRoom.Note] {
        let iso = ISO8601DateFormatter()
        let lead = HomeClubItem(commentId: "n1", mediaId: 4, mediaType: medium == .manga ? "manga" : "anime",
                                spoilerScope: "none", text: "Just one more. Famous last words.", displayName: "Mina",
                                createdAt: iso.string(from: now.addingTimeInterval(-7_200)))
        let spoiler = HomeClubItem(commentId: "n2", mediaId: 4, mediaType: medium == .manga ? "manga" : "anime",
                                   spoilerScope: "ending", text: nil, displayName: "Mina",
                                   createdAt: iso.string(from: now.addingTimeInterval(-9_000)))
        let title = medium == .manga ? "Berserk" : "Death Note"
        let cover = art(medium == .manga ? "manga3.jpg" : "anime0.jpg")
        return [HomeClubRoom.Note(item: lead, title: title, coverImage: cover),
                HomeClubRoom.Note(item: spoiler, title: title, coverImage: cover)]
    }

    // MARK: Composition (Home order: switch, opening line stand-in, leaves, calendar, club, footer)

    private struct MangaHomeFixture: View {
        let width: CGFloat
        @State private var medium: MediaKind = .manga

        private var small: Bool { width <= 360 }
        private var gutter: CGFloat { small ? 17 : 22 }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Lane 4 owns the switch placement, glance and opening line; drawn here only for context.
                KuroMediumSwitch(selection: $medium, size: .large)
                    .padding(.horizontal, small ? 16 : 20)
                    .padding(.top, 7)
                    .padding(.bottom, 18)
                HStack(alignment: .firstTextBaseline) {
                    Text("NOW READING").font(.system(size: small ? 8 : 9)).tracking(1.05)
                        .foregroundStyle(Color(hex: "666C68"))
                    Spacer()
                    Text("4 new chapters").font(.system(size: small ? 13 : 14, weight: .semibold)).tracking(-0.3)
                }
                .padding(.horizontal, small ? 16 : 20)
                .padding(.bottom, 18)
                HomeMangaLeaves(cards: HomeMangaLaneSnapshotTests.mangaCards, containerWidth: width - gutter * 2,
                                readout: { card in
                                    .init(label: String(card.progress), caughtUp: false,
                                          spoken: "Chapter \(card.progress)")
                                },
                                onOpen: { _ in }) { card in
                    KuroAdvanceKey(style: .dark, accessibilityText: "Mark chapter \(card.progress + 1) read") {}
                }
                .padding(.horizontal, gutter)
                HomeCalendarCard(groups: HomeCalendarPresentation.groups(HomeMangaLaneSnapshotTests.mangaSchedule,
                                                                         copy: ReleaseCopy.current(now: HomeMangaLaneSnapshotTests.now)),
                                 coverage: .complete, now: HomeMangaLaneSnapshotTests.now)
                    .padding(.horizontal, small ? 18 : 22)
                    .padding(.top, 32)
                HomeClubRoom(club: HomeMangaLaneSnapshotTests.sundayClub,
                             notes: HomeMangaLaneSnapshotTests.roomNotes(.manga),
                             otherClubCount: 0, medium: .manga, now: HomeMangaLaneSnapshotTests.now)
                    .padding(.horizontal, gutter - 5)
                    .padding(.top, 32)
                    .padding(.bottom, 20) // Home's paper feed (lane 4) pads 20 under the room.
                HomeFooter()
                    .padding(.horizontal, 22)
            }
            .frame(width: width)
            .background(Color.kuroCanvasHomeManga)
        }
    }

    private struct AnimeLowerFixture: View {
        let width: CGFloat

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HomeCalendarCard(groups: HomeCalendarPresentation.groups(HomeMangaLaneSnapshotTests.animeSchedule,
                                                                         copy: ReleaseCopy.current(now: HomeMangaLaneSnapshotTests.now)),
                                 coverage: .complete, now: HomeMangaLaneSnapshotTests.now)
                    .padding(.horizontal, 22)
                    .padding(.top, 32)
                HomeClubRoom(club: HomeMangaLaneSnapshotTests.sundayClub,
                             notes: HomeMangaLaneSnapshotTests.roomNotes(.anime),
                             otherClubCount: 2, medium: .anime, now: HomeMangaLaneSnapshotTests.now, onOpenClubs: {})
                    .padding(.horizontal, 17)
                    .padding(.top, 32)
                    .padding(.bottom, 20) // Home's paper feed (lane 4) pads 20 under the room.
                HomeFooter()
                    .padding(.horizontal, 22)
            }
            .frame(width: width)
            .background(Color.kuroCanvasHome)
        }
    }

    @Test("Manga Home components in Home order at 320/390/430; anime calendar + club at 390")
    func renders() async {
        Self.seedArtwork()
        for width: CGFloat in [390, 320, 430] {
            await render(MangaHomeFixture(width: width), width: width, name: "home-manga-busy-\(Int(width)).png")
        }
        await render(AnimeLowerFixture(width: 390), width: 390, name: "home-anime-calendar-club-390.png")
        // AX5: the app's type scale (`KuroTypeScale`, read by every `kuroCustom` size) and the
        // environment both at accessibility 5, then restored.
        let savedCategory = KuroTypeScale.current.category
        KuroTypeScale.current.update(.accessibility5)
        await render(AnimeLowerFixture(width: 390).environment(\.dynamicTypeSize, .accessibility5), width: 390,
                     name: "home-anime-calendar-club-ax5-390.png")
        await render(MangaHomeFixture(width: 390).environment(\.dynamicTypeSize, .accessibility5), width: 390,
                     name: "home-manga-busy-ax5-390.png")
        KuroTypeScale.current.update(category: savedCategory ?? .large)
        await render(VStack(spacing: 24) {
            HomeMangaLeavesLoading(containerWidth: 346).padding(.horizontal, 22)
            HomeCalendarCard(groups: [], coverage: .pending, now: Self.now, medium: .manga).padding(.horizontal, 22)
            HomeClubRoomFailure(medium: .manga, onRetry: {}).padding(.horizontal, 17)
            HomeClubRoomFailure(medium: .manga, offline: true, onRetry: {}).padding(.horizontal, 17)
            HomeClubRoom(club: Self.sundayClub, notes: [], medium: .anime, now: Self.now,
                         notesFailed: true, onRetry: {}).padding(.horizontal, 17)
        }
        .padding(.vertical, 24)
        .frame(width: 390)
        .background(Color.kuroCanvasHomeManga), width: 390, name: "home-manga-states-390.png")
    }

    // MARK: Render

    private func render<V: View>(_ view: V, width: CGFloat, name: String) async {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            Issue.record("could not create \(Self.outDir.path): \(error)")
            return
        }
        // Warm pass: lay out once so the images start loading, then measure the settled height
        // (the same view measured again once its state and artwork have settled). No device safe
        // area, and the content keeps its ideal height, so the fixed frame never flattens rows
        // that grow at accessibility sizes.
        let probe = UIHostingController(rootView: view)
        probe.safeAreaRegions = []
        let first = probe.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        try? await Task.sleep(for: .milliseconds(500))
        let settledProbe = UIHostingController(rootView: view)
        settledProbe.safeAreaRegions = []
        let settled = settledProbe.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let height = max(200, ceil(max(first.height, settled.height)))
        let host = UIHostingController(rootView: view.fixedSize(horizontal: false, vertical: true)
            .frame(width: width, height: height, alignment: .top))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(1_500))
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { Issue.record("\(name): PNG encoding failed"); return }
        let url = Self.outDir.appendingPathComponent(name)
        do {
            try data.write(to: url)
        } catch {
            Issue.record("\(name): write failed (\(error))")
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
