//
//  ReleaseScheduleTests.swift
//  KuroTests
//
//  Lane F foundation (overnight 2026-11-01), release_precision by lane 3 (spec §3.3a): the release
//  certainty copy (spec D10), the lenient
//  release/theme decoding (spec §3.1–3.3), the "not deployed" fallback of `ReleasesStore`
//  (spec §3.4) and the listen links (spec D11). Every formatting test pins now, language, locale
//  and time zone.
//

import Foundation
import KuroCore
import KuroLibrary
import Supabase
import Testing
@testable import Kuro

@MainActor
@Suite("Release certainty copy")
struct ReleaseCopyTests {
    /// Wed 14 Oct 2026, 12:00 UTC.
    nonisolated static let now = Date(timeIntervalSince1970: 1_791_979_200)
    nonisolated static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
    nonisolated static let utc = TimeZone(identifier: "UTC") ?? .current

    static func english(_ zone: TimeZone = utc) -> ReleaseCopy {
        ReleaseCopy(now: now, german: false, locale: Locale(identifier: "en_GB"), timeZone: zone)
    }

    static func german() -> ReleaseCopy {
        ReleaseCopy(now: now, german: true, locale: Locale(identifier: "de_DE"), timeZone: berlin)
    }

    static func item(_ kind: ReleaseUnitKind, _ number: Double?, at date: Date?, basis: ReleaseBasis,
                     confidence: Double? = nil, medium: MediaKind = .anime, isPast: Bool = false,
                     source: String = "anilist") -> ReleaseScheduleItem {
        ReleaseScheduleItem(medium: medium, mediaId: 1, title: "Title", unitKind: kind, unitNumber: number,
                            releaseAt: date, basis: basis, confidence: confidence, source: source, isPast: isPast)
    }

    /// Thu 15 Oct 2026, 16:30 UTC (18:30 in Berlin).
    static let thursday = Date(timeIntervalSince1970: 1_792_081_800)

    @Test("Confirmed: unit, weekday, date and time (EN device locale, DE de_DE + Europe/Berlin)")
    func confirmed() {
        // Fri 16 Oct 2026, 16:30 UTC: two days after `now`, so no relative day replaces the date.
        let friday = Self.thursday.addingTimeInterval(86_400)
        let row = Self.item(.episode, 7, at: friday, basis: .confirmed)
        #expect(Self.english(Self.berlin).line(row) == "Ep. 7 · Fri 16 Oct, 18:30")
        #expect(Self.german().line(row) == "F. 7 · Fr. 16. Okt., 18:30")
    }

    @Test("Relative day: today and tomorrow replace the date")
    func relative() {
        let tonight = Self.now.addingTimeInterval(6 * 3_600)
        let row = Self.item(.episode, 3, at: tonight, basis: .confirmed)
        #expect(Self.english().line(row) == "Ep. 3 · Today, 18:00")
        #expect(Self.german().line(row) == "F. 3 · Heute, 20:00")
        let tomorrow = Self.item(.chapter, 12, at: Self.thursday, basis: .announced, medium: .manga)
        #expect(Self.english().line(tomorrow) == "Ch. 12 · Tomorrow")
        #expect(Self.german().line(tomorrow) == "Kap. 12 · Morgen")
    }

    @Test("Announced: a first-of-month midnight UTC date is a month window, in every zone")
    func announcedMonth() {
        let november = Date(timeIntervalSince1970: 1_793_491_200) // 1 Nov 2026 00:00 UTC
        let row = Self.item(.volume, 115, at: november, basis: .announced, medium: .manga)
        #expect(Self.english().line(row) == "Vol. 115 · November")
        #expect(Self.english(TimeZone(identifier: "America/Los_Angeles") ?? .current).line(row) == "Vol. 115 · November")
        #expect(Self.german().line(row) == "Bd. 115 · November")
        let nextYear = Date(timeIntervalSince1970: 1_801_440_000) // 1 Feb 2027 00:00 UTC
        #expect(Self.english().line(Self.item(.volume, 116, at: nextYear, basis: .announced, medium: .manga))
                == "Vol. 116 · February 2027")
    }

    @Test("Announced: any other date is a day without a time")
    func announcedDay() {
        let saturday = Date(timeIntervalSince1970: 1_792_238_400) // Sat 17 Oct 2026 12:00 UTC
        let row = Self.item(.volume, 9, at: saturday, basis: .announced, medium: .manga)
        #expect(Self.english().line(row) == "Vol. 9 · Sat 17 Oct")
        #expect(Self.german().line(row) == "Bd. 9 · Sa. 17. Okt.")
        // A day-only value stored at 00:00 UTC is still that day west of UTC.
        let midnight = Date(timeIntervalSince1970: 1_792_195_200) // Sat 17 Oct 2026 00:00 UTC
        let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let day = Self.item(.volume, 9, at: midnight, basis: .announced, medium: .manga)
        #expect(Self.english(losAngeles).line(day) == "Vol. 9 · Sat 17 Oct")
        #expect(Self.english(losAngeles).accessibilityLine(day) == "Volume 9, Saturday 17 October")
        // Thu 15 Oct 00:00 UTC is tomorrow for a reader in Los Angeles on Wed 14 Oct.
        let thursdayMidnight = Self.item(.volume, 10, at: Date(timeIntervalSince1970: 1_792_022_400),
                                         basis: .announced, medium: .manga)
        #expect(Self.english(losAngeles).line(thursdayMidnight) == "Vol. 10 · Tomorrow")
    }

    @Test("Estimated: 'expected around', shown only at confidence ≥ 0.7")
    func estimated() {
        let sunday = Date(timeIntervalSince1970: 1_792_324_800) // Sun 18 Oct 2026 12:00 UTC
        let row = Self.item(.chapter, 1197, at: sunday, basis: .estimated, confidence: 0.82, medium: .manga)
        #expect(Self.english().line(row) == "Ch. 1197 · expected around Sun 18 Oct")
        #expect(Self.german().line(row) == "Kap. 1197 · voraussichtlich am So. 18. Okt.")
        #expect(Self.german().accessibilityLine(row) == "Kapitel 1197, voraussichtlich am Sonntag, 18. Oktober")
        let soon = Self.item(.chapter, 1198, at: Self.thursday, basis: .estimated, confidence: 0.9, medium: .manga)
        #expect(Self.english().accessibilityLine(soon) == "Chapter 1198, expected tomorrow")
        let weak = Self.item(.chapter, 1197, at: sunday, basis: .estimated, confidence: 0.5, medium: .manga)
        #expect(!weak.isDisplayable)
        #expect(Self.english().datePhrase(weak) == nil)
        let missing = Self.item(.chapter, 1197, at: sunday, basis: .estimated, confidence: nil, medium: .manga)
        #expect(!missing.isDisplayable)
    }

    @Test("No date: the unit alone, 'Dates to come.' only when asked to fill a slot")
    func undated() {
        let row = Self.item(.episode, 8, at: nil, basis: .confirmed)
        #expect(Self.english().line(row) == "Ep. 8")
        #expect(Self.english().line(row, undatedFallback: true) == "Ep. 8 · Dates to come.")
        #expect(Self.german().line(row, undatedFallback: true) == "F. 8 · Termine folgen.")
    }

    @Test("Units: fractional chapters, unknown numbers, seasons, spoken labels")
    func units() {
        let half = Self.item(.chapter, 1197.5, at: nil, basis: .confirmed, medium: .manga)
        #expect(Self.english().unitLabel(half) == "Ch. 1197.5")
        #expect(Self.german().unitLabel(half) == "Kap. 1197,5")
        #expect(Self.english().unitLabel(Self.item(.volume, nil, at: nil, basis: .announced)) == "Next volume")
        #expect(Self.german().unitLabel(Self.item(.season, 2, at: nil, basis: .announced)) == "Staffel 2")
        #expect(Self.english().unitSpokenLabel(Self.item(.episode, 7, at: nil, basis: .confirmed)) == "Episode 7")
    }

    // MARK: release_precision (spec §3.3a)

    static func precise(_ kind: ReleaseUnitKind, _ number: Double?, at date: Date?, basis: ReleaseBasis,
                        precision: ReleasePrecision, confidence: Double? = nil,
                        medium: MediaKind = .manga) -> ReleaseScheduleItem {
        ReleaseScheduleItem(medium: medium, mediaId: 1, title: "Title", unitKind: kind, unitNumber: number,
                            releaseAt: date, basis: basis, confidence: confidence, source: "mangaupdates",
                            precision: precision)
    }

    /// 1 Nov 2026 00:00 UTC (a Sunday).
    static let firstOfNovember = Date(timeIntervalSince1970: 1_793_491_200)
    /// Sat 17 Oct 2026 00:00 in Tokyo (Fri 16 Oct 15:00 UTC).
    static let saturdayTokyoMidnight = Date(timeIntervalSince1970: 1_792_162_800)

    @Test("Absent precision is inferred exactly as before the column existed")
    func inferredPrecision() {
        #expect(Self.item(.episode, 1, at: Self.thursday, basis: .confirmed).effectivePrecision == .instant)
        #expect(Self.item(.volume, 1, at: Self.firstOfNovember, basis: .announced).effectivePrecision == .month)
        #expect(Self.item(.volume, 1, at: Self.thursday, basis: .announced).effectivePrecision == .day)
        #expect(Self.item(.chapter, 1, at: Self.thursday, basis: .estimated, confidence: 0.9).effectivePrecision == .day)
        #expect(Self.item(.volume, 1, at: nil, basis: .announced).effectivePrecision == .day)
    }

    @Test("Day precision: a date without a time, even on the 1st of a month")
    func dayPrecision() {
        let row = Self.precise(.volume, 115, at: Self.firstOfNovember, basis: .announced, precision: .day)
        #expect(Self.english().line(row) == "Vol. 115 · Sun 1 Nov", "an explicit day is never read as a month window")
        #expect(Self.german().line(row) == "Bd. 115 · So. 1. Nov.")
        #expect(!row.showsTime)
        // A source-zone midnight east of UTC (Tokyo) keeps its source date in every reader zone.
        let tokyo = Self.precise(.chapter, 12, at: Self.saturdayTokyoMidnight, basis: .announced, precision: .day)
        let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .current
        #expect(Self.english(losAngeles).line(tokyo) == "Ch. 12 · Sat 17 Oct")
        #expect(Self.german().line(tokyo) == "Kap. 12 · Sa. 17. Okt.")
        #expect(Self.english().accessibilityLine(tokyo) == "Chapter 12, Saturday 17 October")
        // A confirmed row that only carries a day never shows a time.
        let confirmedDay = Self.precise(.episode, 4, at: Self.firstOfNovember, basis: .confirmed, precision: .day, medium: .anime)
        #expect(Self.english().line(confirmedDay) == "Ep. 4 · Sun 1 Nov")
        #expect(Self.english().accessibilityLine(confirmedDay) == "Episode 4, Sunday 1 November")
    }

    @Test("Month, quarter and year windows")
    func windows() {
        // 1 Nov 00:00 in Tokyo is 31 Oct 15:00 UTC: still November.
        let november = Self.precise(.volume, 115, at: Date(timeIntervalSince1970: 1_793_458_800), basis: .announced, precision: .month)
        #expect(Self.english().line(november) == "Vol. 115 · November")
        #expect(Self.german().line(november) == "Bd. 115 · November")
        let januaryNextYear = Date(timeIntervalSince1970: 1_798_761_600) // 1 Jan 2027 00:00 UTC
        let quarter = Self.precise(.volume, 116, at: januaryNextYear, basis: .announced, precision: .quarter)
        #expect(Self.english().line(quarter) == "Vol. 116 · Q1 2027")
        #expect(Self.german().line(quarter) == "Bd. 116 · Q1 2027")
        let year = Self.precise(.season, 2, at: januaryNextYear, basis: .announced, precision: .year, medium: .anime)
        #expect(Self.english().line(year) == "Season 2 · 2027")
        #expect(Self.english().accessibilityLine(year) == "Season 2, 2027")
        let estimatedQuarter = Self.precise(.volume, 117, at: januaryNextYear, basis: .estimated, precision: .quarter, confidence: 0.8)
        #expect(Self.english().line(estimatedQuarter) == "Vol. 117 · expected in Q1 2027")
        #expect(Self.german().line(estimatedQuarter) == "Bd. 117 · voraussichtlich im Q1 2027")
        let estimatedYear = Self.precise(.volume, 118, at: januaryNextYear, basis: .estimated, precision: .year, confidence: 0.8)
        #expect(Self.german().line(estimatedYear) == "Bd. 118 · voraussichtlich 2027")
        #expect(Self.english().calendarDay(november) == nil, "a window has no calendar day")
    }

    @Test("Only an instant shows a time; an estimated instant shows its day")
    func instantOnlyTime() {
        let friday = Self.thursday.addingTimeInterval(86_400)
        let confirmed = Self.precise(.episode, 7, at: friday, basis: .confirmed, precision: .instant, medium: .anime)
        #expect(Self.english(Self.berlin).line(confirmed) == "Ep. 7 · Fri 16 Oct, 18:30")
        #expect(confirmed.showsTime)
        let estimated = Self.precise(.chapter, 9, at: friday, basis: .estimated, precision: .instant, confidence: 0.9)
        #expect(Self.english(Self.berlin).line(estimated) == "Ch. 9 · expected around Fri 16 Oct")
        #expect(!estimated.showsTime)
    }

    @Test("Calendar day and heading follow the date phrase's reading")
    func calendarDays() throws {
        let instant = Self.item(.episode, 3, at: Self.thursday, basis: .confirmed)
        let instantDay = try #require(Self.german().calendarDay(instant))
        #expect(instantDay.year == 2026 && instantDay.month == 10 && instantDay.day == 15)
        let tokyo = Self.precise(.chapter, 12, at: Self.saturdayTokyoMidnight, basis: .announced, precision: .day)
        let tokyoDay = try #require(Self.english().calendarDay(tokyo))
        #expect(tokyoDay.day == 17)
        #expect(Self.english().calendarDay(Self.item(.episode, 1, at: nil, basis: .confirmed)) == nil)
        let tomorrow = try #require(Self.english().dayHeading(instantDay))
        #expect(tomorrow.label == "Tomorrow" && tomorrow.day == "15" && tomorrow.month == "Oct")
        let saturday = try #require(Self.english().dayHeading(tokyoDay))
        #expect(saturday.label == "Sat 17 Oct" && saturday.day == "17")
        #expect(Self.german().dayHeading(instantDay)?.label == "Morgen")
    }

    @Test("Past rows and source attribution")
    func pastAndSource() {
        let row = Self.item(.episode, 6, at: Self.now.addingTimeInterval(-6 * 86_400), basis: .confirmed, isPast: true)
        #expect(Self.english().line(row) == "Ep. 6 · released Thu 8 Oct")
        #expect(Self.english().sourceAttribution(row) == "via AniList")
        #expect(Self.german().sourceAttribution(row) == "über AniList")
        #expect(Self.english().sourceAttribution(Self.item(.chapter, 1, at: nil, basis: .estimated, source: "unknown")) == nil)
    }
}

@MainActor
@Suite("Release models: lenient decoding and ordering")
struct ReleaseModelTests {
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    @Test("One bad row never blanks the list; numeric strings and missing columns are tolerated")
    func lenientRows() throws {
        let json = """
        [
          {"medium":"anime","media_id":1,"title":"A","cover_image":null,"unit_kind":"episode","unit_number":7,
           "unit_label":"Ep. 7","release_at":"2026-10-15T16:30:00Z","basis":"confirmed","confidence":1,
           "source":"anilist","source_url":"https://anilist.co/anime/1"},
          {"medium":"manga","media_id":2,"title":"B","unit_kind":"chapter","unit_number":"1197.5",
           "release_at":null,"basis":"estimated","confidence":"0.8","source":"kuro_estimate","source_url":"javascript:alert(1)"},
          {"medium":"anime","media_id":3,"title":"C","basis":"rumoured","source":"x"},
          {"medium":"podcast","media_id":4,"basis":"confirmed"}
        ]
        """
        let rows = try Self.decode(LenientRows<ReleaseScheduleItem>.self, json)
        #expect(rows.rows.count == 2)
        #expect(rows.skipped == 2)
        let manga = try #require(rows.rows.last)
        #expect(manga.unitNumber == 1197.5)
        #expect(manga.confidence == 0.8)
        #expect(manga.sourceURL == nil, "only http(s) links are kept")
        #expect(manga.isPast == false)
        #expect(rows.rows.first?.sourceURL?.host == "anilist.co")
    }

    @Test("release_precision: decoded when known; absent or unknown words keep the row and infer")
    func precisionDecoding() throws {
        let json = """
        [{"medium":"manga","media_id":1,"unit_kind":"volume","unit_number":3,"release_at":"2027-01-01T00:00:00Z","basis":"announced","source":"mangaupdates","release_precision":"quarter"},
         {"medium":"manga","media_id":2,"unit_kind":"volume","unit_number":4,"release_at":"2026-11-01T00:00:00Z","basis":"announced","source":"mangaupdates","release_precision":"fortnight"},
         {"medium":"anime","media_id":3,"unit_kind":"episode","unit_number":5,"release_at":"2026-10-15T16:30:00Z","basis":"confirmed","source":"anilist","release_precision":null},
         {"medium":"anime","media_id":4,"unit_kind":"episode","unit_number":6,"release_at":"2026-10-15T16:30:00Z","basis":"confirmed","source":"anilist","is_past":true,"release_precision":"INSTANT"}]
        """
        let rows = try Self.decode(LenientRows<ReleaseScheduleItem>.self, json)
        #expect(rows.rows.count == 4 && rows.skipped == 0)
        #expect(rows.rows.map(\.precision) == [.quarter, nil, nil, .instant])
        #expect(rows.rows.map(\.effectivePrecision) == [.quarter, .month, .instant, .instant])
        #expect(rows.rows.last?.isPast == true)
    }

    @Test("Unknown unit kind falls back per medium")
    func unitKindFallback() throws {
        let rows = try Self.decode(LenientRows<ReleaseScheduleItem>.self,
            #"[{"medium":"manga","media_id":2,"unit_kind":"omake","basis":"announced","source":"publisher"}]"#)
        #expect(rows.rows.first?.unitKind == .chapter)
    }

    @Test("Ordering: displayable only, past first when kept, soonest first, undated last")
    func ordering() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func row(_ id: Int, _ at: Date?, basis: ReleaseBasis = .confirmed, confidence: Double? = nil, past: Bool = false) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: .anime, mediaId: id, title: "T\(id)", unitKind: .episode, unitNumber: 1,
                                releaseAt: at, basis: basis, confidence: confidence, source: "anilist", isPast: past)
        }
        let items = [row(1, nil), row(2, base.addingTimeInterval(60)), row(3, base),
                     row(4, base, basis: .estimated, confidence: 0.4), row(5, base.addingTimeInterval(-60), past: true)]
        #expect(ReleaseSchedulePolicy.prepared(items, keepPast: false).map(\.mediaId) == [3, 2, 1])
        #expect(ReleaseSchedulePolicy.prepared(items, keepPast: true).map(\.mediaId) == [5, 3, 2, 1])
    }

    @Test("Themes: reading order, adult rows dropped, labels and listen search links")
    func themes() throws {
        let json = """
        [{"kind":"ED","sequence":1,"title":"Night","artist":"B","episodes":"1–12","version":null,"is_spoiler":false,"is_nsfw":false,"source":"animethemes","source_url":null},
         {"kind":"OP","sequence":2,"title":"Second","artist":null,"is_spoiler":true,"is_nsfw":false},
         {"kind":"OP","sequence":1,"title":"Tank! & Co","artist":"Seatbelts","is_spoiler":false,"is_nsfw":false},
         {"kind":"IN","sequence":1,"title":"Hidden","is_nsfw":true},
         {"kind":"XX","title":"Bad"}]
        """
        let rows = try Self.decode(LenientRows<ThemeSong>.self, json)
        #expect(rows.skipped == 1)
        let songs = ReleaseSchedulePolicy.preparedThemes(rows.rows)
        #expect(songs.map(\.label) == ["OP1", "OP2", "ED1"])
        let first = try #require(songs.first)
        #expect(first.searchQuery == "Tank! & Co Seatbelts")
        #expect(first.appleMusicSearchURL?.absoluteString == "https://music.apple.com/search?term=Tank%21%20%26%20Co%20Seatbelts")
        #expect(first.spotifySearchURL?.absoluteString == "https://open.spotify.com/search/Tank%21%20%26%20Co%20Seatbelts")
        #expect(ThemeListenLinks.spotifySearch("   ") == nil)
    }
}

@MainActor
@Suite("Release contract fallback", .timeLimit(.minutes(1)))
struct ReleaseContractFallbackTests {
    static let userA = LifecycleFixtures.userA

    nonisolated static let notFound = StubResponse.json(#"{"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function"}"#, status: 404)

    @Test("Failure classes: a missing contract falls back and is remembered; a transient one is not cached")
    func classification() {
        #expect(ReleaseFailure.classify(PostgrestError(code: "PGRST202", message: "missing")) == .notDeployed)
        #expect(ReleaseFailure.classify(PostgrestError(code: "PGRST205", message: "missing table")) == .notDeployed)
        #expect(ReleaseFailure.classify(PostgrestError(code: "42883", message: "undefined function")) == .notDeployed)
        #expect(ReleaseFailure.classify(PostgrestError(code: "57014", message: "timeout")) == .transient)
        #expect(ReleaseFailure.classify(URLError(.notConnectedToInternet)) == .transient)
        #expect(ReleaseFailure.classify(URLError(.cancelled)) == .cancelled)
        #expect(ReleaseFailure.classify(CancellationError()) == .cancelled)
        #expect(ReleaseFailure.classify(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))) == .notDeployed)
    }

    @Test("Schedule RPC not deployed: anime next episodes from user_airing_next, cached, contract not re-asked")
    func scheduleFallsBackSilently() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/user_release_schedule_v1": return Self.notFound
            case "user_airing_next": return ReleasesContractTests.upcoming(42, inHours: 5)
            default: return .emptyArray
            }
        }
        let releases = harness.service.releases
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")

        let items = await releases.loadSchedule()
        #expect(items.map(\.mediaId) == [42])
        #expect(items.first?.basis == .confirmed)
        #expect(items.first?.unitNumber == 3)
        #expect(releases.scheduleSource == .airingFallback)
        #expect(releases.nextRelease(for: MediaKey(kind: .anime, id: 42))?.mediaId == 42)
        #expect(harness.requests(to: "rpc/user_release_schedule_v1").count == 1)

        // Cached for the account, and the missing contract is not asked again even when forced.
        _ = await releases.loadSchedule()
        _ = await releases.loadSchedule(force: true)
        #expect(harness.requests(to: "rpc/user_release_schedule_v1").count == 1)

        // A new account starts with nothing.
        await harness.service.session.endSession()
        #expect(releases.schedule.isEmpty && releases.scheduleSource == .none)
        await harness.tearDown()
    }

    @Test("Schedule RPC deployed: rows decoded leniently, low-confidence estimates dropped, account-scoped")
    func scheduleFromContract() async throws {
        let soon = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3_600))
        let later = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400))
        let body = """
        [{"medium":"manga","media_id":9,"title":"M","unit_kind":"chapter","unit_number":1197,"release_at":"\(later)","basis":"estimated","confidence":0.9,"source":"kuro_estimate"},
         {"medium":"manga","media_id":10,"title":"W","unit_kind":"chapter","unit_number":5,"release_at":"\(soon)","basis":"estimated","confidence":0.3,"source":"kuro_estimate"},
         {"medium":"anime","media_id":42,"title":"A","unit_kind":"episode","unit_number":4,"release_at":"\(soon)","basis":"confirmed","confidence":1,"source":"anilist"},
         {"medium":"anime","media_id":43,"basis":"rumoured"}]
        """
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/user_release_schedule_v1" ? .json(body) : .emptyArray
        }
        let releases = harness.service.releases
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")

        let items = await releases.loadSchedule()
        #expect(items.map(\.mediaId) == [42, 9])
        #expect(releases.scheduleSource == .schedule)
        #expect(releases.scheduleItems(for: .manga).map(\.mediaId) == [9])
        let request = try #require(harness.requests(to: "rpc/user_release_schedule_v1").first)
        #expect(request.method == "POST")
        await harness.tearDown()
    }

    @Test("Schedule fallback whose user_airing_next read fails is not cached")
    func failedFallbackIsNotCached() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/user_release_schedule_v1": return Self.notFound
            case "user_airing_next": return .json(#"{"message":"unavailable"}"#, status: 503)
            default: return .emptyArray
            }
        }
        let releases = harness.service.releases
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        releases.lastUpcomingFetchAt = nil
        releases.upcomingBackoff = ReleasesStore.BackoffState()

        let items = await releases.loadSchedule()
        #expect(items.isEmpty)
        #expect(releases.scheduleSource == .airingFallback)
        #expect(releases.scheduleCache.isEmpty, "an empty fallback from a failed read must not be served for 5 minutes")
        await harness.tearDown()
    }

    @Test("A status edit back to watching refreshes upcoming airings (the own echo no longer does)")
    func statusEditRefreshesUpcoming() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "user_airing_next" ? ReleasesContractTests.upcoming(42, inHours: 5) : .emptyArray
        }
        let releases = harness.service.releases
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        let account = try #require(releases.accountSession.current)
        let key = MediaKey(kind: .anime, id: 42)
        func entry(_ status: ListStatus, progress: Int = 2) -> LibraryEntry {
            LibraryEntry(key: key, rowId: 9, status: status, progress: progress, createdAt: Date(), updatedAt: Date())
        }

        // Dropped: the row and countdown leave.
        releases.libraryDidChange(LibraryChange(key: key, kind: .updated, previous: entry(.current),
                                                current: entry(.dropped), mutationId: UUID(), account: account))
        #expect(releases.upcomingAirings.allSatisfy { $0.anime_id != 42 })

        // Back to watching: user_airing_next is read again (outside the throttle window).
        releases.lastUpcomingFetchAt = nil
        let before = harness.requests(to: "user_airing_next").count
        releases.libraryDidChange(LibraryChange(key: key, kind: .updated, previous: entry(.dropped),
                                                current: entry(.current), mutationId: UUID(), account: account))
        await releases.libraryChangeTask?.value
        #expect(harness.requests(to: "user_airing_next").count == before + 1)
        #expect(releases.upcomingAirings.map(\.anime_id) == [42])

        // A plain edit with the same status reads nothing.
        releases.lastUpcomingFetchAt = nil
        let afterStatus = harness.requests(to: "user_airing_next").count
        var rated = entry(.current)
        rated.rating = UserRating(value: 8)
        releases.libraryDidChange(LibraryChange(key: key, kind: .updated, previous: entry(.current),
                                                current: rated, mutationId: UUID(), account: account))
        await releases.libraryChangeTask?.value
        #expect(harness.requests(to: "user_airing_next").count == afterStatus)
        await harness.tearDown()
    }

    @Test("Themes RPC not deployed: empty (the section hides), remembered, no second request")
    func themesHideWhenMissing() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/media_themes_v1" ? Self.notFound : .emptyArray
        }
        let releases = harness.service.releases
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")

        #expect(await releases.themes(animeId: 1).isEmpty)
        #expect(await releases.themes(animeId: 2).isEmpty)
        #expect(harness.requests(to: "rpc/media_themes_v1").count == 1)
        await harness.tearDown()
    }

    @Test("Media schedule offline: the anime fallback is used and nothing is cached")
    func mediaScheduleTransientNotCached() async throws {
        let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(7_200))
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/media_release_schedule_v1": return .json(#"{"message":"unavailable"}"#, status: 503)
            case "anime": return .json(#"[{"id":5,"title_english":"Five","title_romaji":null,"next_episode_number":2,"next_airing_at":"\#(at)"}]"#)
            default: return .emptyArray
            }
        }
        let releases = harness.service.releases
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")

        let first = await releases.mediaSchedule(kind: .anime, id: 5)
        #expect(first.map(\.unitNumber) == [2])
        _ = await releases.mediaSchedule(kind: .anime, id: 5)
        #expect(harness.requests(to: "rpc/media_release_schedule_v1").count == 2, "a transient failure is retried")
        #expect(await releases.mediaSchedule(kind: .manga, id: 5).isEmpty)
        await harness.tearDown()
    }
}
