import Foundation
import KuroCore
import KuroLibrary
import Testing
import KuroWidgetSupport
import WidgetKit
@testable import Kuro

@MainActor
@Suite("Tier 1 & Tier 2 capabilities")
struct Tier1Tier2CapabilitiesTests {
    private static let epoch = Date(timeIntervalSince1970: 1_793_707_200) // Mon 2026-11-03 12:00 UTC

    private static func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? epoch
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func makeFolioItem(
        id: Int,
        kind: MediaKind = .manga,
        title: String = "Test Title",
        episodes: Int? = nil,
        chapters: Int? = nil,
        rating: Double? = nil,
        genres: [String]? = nil,
        statusRaw: String? = "RELEASING",
        formatRaw: String? = "MANGA",
        listStatus: ListStatus = .planning,
        progress: Int = 0
    ) -> FolioItem {
        let media = Media(
            id: id,
            kind: kind,
            title: title,
            imageURL: nil,
            year: "2024",
            displayDescription: "",
            episodes: episodes,
            chapters: chapters,
            rating: rating,
            genres: genres,
            statusRaw: statusRaw,
            formatRaw: formatRaw,
            popularityValue: 100,
            trendingValue: 10,
            createdAtValue: nil
        )
        let entry = LibraryEntry(
            key: MediaKey(kind: kind, id: id),
            rowId: id,
            status: listStatus,
            progress: progress,
            createdAt: Self.epoch,
            updatedAt: Self.epoch
        )
        return FolioItem(media: media, entry: entry, progress: progress, next: nil, banner: nil)
    }

    // MARK: - Wave 1: Browse medium filters & acronym preview matching

    @Test("BrowseView filters separate anime and manga dimensions cleanly")
    func browseMediumSeparation() {
        #expect(BrowseView.LengthFilter.short.applies(toAnime: true))
        #expect(!BrowseView.LengthFilter.short.applies(toAnime: false))
        #expect(BrowseView.LengthFilter.mangaMedium.applies(toAnime: false))
        #expect(!BrowseView.LengthFilter.mangaMedium.applies(toAnime: true))
        #expect(BrowseView.LengthFilter.mangaLong.chapterRange?.min == 101)
        #expect(BrowseView.LengthFilter.mangaLong.chapterRange?.max == 199)

        #expect(!BrowseView.StatusFilter.visibleCases(anime: true).contains(.hiatus))
        #expect(BrowseView.StatusFilter.visibleCases(anime: false).contains(.hiatus))
        #expect(BrowseView.StatusFilter.hiatus.applies(toAnime: false))
        #expect(!BrowseView.StatusFilter.hiatus.applies(toAnime: true))

        #expect(BrowseView.FormatFilter.tv.applies(toAnime: true))
        #expect(!BrowseView.FormatFilter.tv.applies(toAnime: false))
        #expect(BrowseView.FormatFilter.oneShot.applies(toAnime: false))
        #expect(!BrowseView.FormatFilter.oneShot.applies(toAnime: true))

        #expect(BrowseView.genreOrTagTitle("tag:Workplace", german: false) == "Workplace")
        #expect(BrowseView.genreOrTagTitle("tag:Workplace", german: true) == "Arbeitswelt")
        #expect(BrowseView.genreOrTagTitle("tag:Time Manipulation", german: true) == "Zeitreise")
    }

    @Test("EditorialSearchView localPreviewMatches matches multi-word initialisms")
    func searchAcronymPreview() throws {
        let mha: AnimeCard = try decode(#"{"id":1,"title_english":"My Hero Academia","popularity":900}"#)
        let snk: AnimeCard = try decode(#"{"id":2,"title_english":"Attack on Titan","title_romaji":"Shingeki no Kyojin","popularity":800}"#)
        let berserk: MangaCard = try decode(#"{"id":10,"title_english":"Berserk","popularity":950}"#)

        let mhaHits = EditorialSearchView.localPreviewMatches(
            query: "mha",
            scope: .all,
            anime: [mha, snk],
            manga: [berserk]
        )
        #expect(mhaHits.map(\.media.id) == [1])

        let snkHits = EditorialSearchView.localPreviewMatches(
            query: "SNK",
            scope: .anime,
            anime: [mha, snk],
            manga: [berserk]
        )
        #expect(snkHits.map(\.media.id) == [2])
    }

    // MARK: - Wave 2: Planning lens, On Hiatus split, Trailer URLs

    @Test("FolioPlanningFilter and FolioTonightShortlist are deterministic and reshuffle cleanly")
    func planningLensAndShortlist() {
        let shortFinished = makeFolioItem(
            id: 1, kind: .anime, title: "Short Gem", episodes: 12,
            rating: 8.6, genres: ["Drama"], statusRaw: "FINISHED", formatRaw: "TV"
        )
        let longOngoing = makeFolioItem(
            id: 2, kind: .anime, title: "Long Serial", episodes: 120,
            rating: 7.5, genres: ["Action"], statusRaw: "RELEASING", formatRaw: "TV"
        )
        let oneShotManga = makeFolioItem(
            id: 3, kind: .manga, title: "One Shot", chapters: 1,
            rating: 8.4, genres: ["Drama"], statusRaw: "FINISHED", formatRaw: "ONE_SHOT"
        )
        let items = [shortFinished, longOngoing, oneShotManga]

        #expect(FolioPlanningFilter.weekendFinish.matches(shortFinished))
        #expect(!FolioPlanningFilter.weekendFinish.matches(longOngoing))
        #expect(FolioPlanningFilter.weekendFinish.matches(oneShotManga))
        #expect(FolioPlanningFilter.bingeReady.matches(shortFinished))
        #expect(!FolioPlanningFilter.bingeReady.matches(longOngoing))
        #expect(FolioPlanningFilter.acclaimed.matches(shortFinished))
        #expect(!FolioPlanningFilter.acclaimed.matches(longOngoing))
        #expect(FolioPlanningFilter.genre("Drama").matches(shortFinished))
        #expect(!FolioPlanningFilter.genre("Drama").matches(longOngoing))

        let pickA = FolioTonightShortlist.picks(from: items, accountId: "u1", dayOrdinal: 20_000, reshuffleSeed: 0, limit: 2)
        let pickB = FolioTonightShortlist.picks(from: items, accountId: "u1", dayOrdinal: 20_000, reshuffleSeed: 0, limit: 2)
        #expect(pickA.map(\.key) == pickB.map(\.key))
        #expect(pickA.count == 2)

        let extraPool = items + [
            makeFolioItem(id: 4, kind: .anime, title: "Pick Four", episodes: 10, rating: 8.5, statusRaw: "FINISHED", formatRaw: "TV"),
            makeFolioItem(id: 5, kind: .anime, title: "Pick Five", episodes: 11, rating: 8.3, statusRaw: "FINISHED", formatRaw: "TV"),
        ]
        let seed0 = FolioTonightShortlist.picks(from: extraPool, accountId: "u1", dayOrdinal: 20_000, reshuffleSeed: 0, limit: 3).map(\.id)
        let seed1 = FolioTonightShortlist.picks(from: extraPool, accountId: "u1", dayOrdinal: 20_000, reshuffleSeed: 1, limit: 3).map(\.id)
        #expect(seed0 != seed1)
    }

    @Test("Hiatus partition isolates HIATUS manga without affecting anime")
    func hiatusPartitioning() throws {
        let activeManga = makeFolioItem(id: 11, kind: .manga, statusRaw: "RELEASING", listStatus: .current)
        let hiatusManga = makeFolioItem(id: 12, kind: .manga, statusRaw: "HIATUS", listStatus: .current)
        let mangaSplit = FolioPolicy.partitionHiatusManga([activeManga, hiatusManga], medium: .manga, status: .watching)
        #expect(mangaSplit.active.map(\.media.id) == [11])
        #expect(mangaSplit.onHiatus.map(\.media.id) == [12])

        let animeSplit = FolioPolicy.partitionHiatusManga([activeManga, hiatusManga], medium: .anime, status: .watching)
        #expect(animeSplit.onHiatus.isEmpty)
        #expect(animeSplit.active.count == 2)

        let cardActive: HomeCard = try decode(
            #"{"media_id":1,"list_type":"READING","progress":5,"server_revision":1,"lifecycle_id":"11111111-1111-4111-8111-111111111111","title":"A","catalogue_status":"RELEASING"}"#
        )
        let cardHiatus: HomeCard = try decode(
            #"{"media_id":2,"list_type":"READING","progress":50,"server_revision":1,"lifecycle_id":"11111111-1111-4111-8111-111111111112","title":"B","catalogue_status":"HIATUS"}"#
        )
        let homeSplit = HomeShelfPolicy.splitHiatusCards([cardActive, cardHiatus])
        #expect(homeSplit.active.map(\.mediaId) == [1])
        #expect(homeSplit.onHiatus.map(\.mediaId) == [2])
    }

    @Test("DetailTrailerRule selects official HTTPS trailer and skips disabled/non-HTTPS links")
    func trailerSelection() {
        let ts = Date(timeIntervalSince1970: 0)
        let disabled = ExternalLink(
            id: 1, mediaType: "ANIME", mediaId: 7, site: "YouTube",
            url: "https://youtube.com/watch?v=disabled", language: nil, color: nil,
            priority: 1, isDisabled: true, createdAt: ts, updatedAt: ts
        )
        let insecure = ExternalLink(
            id: 2, mediaType: "ANIME", mediaId: 7, site: "Official Trailer",
            url: "http://example.com/trailer", language: nil, color: nil,
            priority: 2, isDisabled: false, createdAt: ts, updatedAt: ts
        )
        let valid = ExternalLink(
            id: 3, mediaType: "ANIME", mediaId: 7, site: "YouTube",
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", language: nil, color: nil,
            priority: 3, isDisabled: false, createdAt: ts, updatedAt: ts
        )
        #expect(DetailTrailerRule.officialTrailerURL(from: [disabled, insecure, valid])?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(DetailTrailerRule.officialTrailerURL(from: [disabled, insecure]) == nil)
    }

    // MARK: - Wave 3: Source chapter bookmark parsing

    @Test("DetailSourceCard.parsedChapterNumber extracts chapter numbers cleanly")
    func sourceChapterParsing() {
        #expect(DetailSourceCard.parsedChapterNumber(from: "Ch. 46") == 46)
        #expect(DetailSourceCard.parsedChapterNumber(from: "Chapter 108") == 108)
        #expect(DetailSourceCard.parsedChapterNumber(from: "Kap. 12") == 12)
        #expect(DetailSourceCard.parsedChapterNumber(from: "Prologue") == nil)
        #expect(DetailSourceCard.parsedChapterNumber(from: nil) == nil)
    }

    // MARK: - Wave 4: Club note spoiler gates

    @Test("ClubSpoilerGate parses tags/server flags and enforces progress/completed unlocking")
    func clubSpoilerGates() throws {
        let parsedInline = ClubSpoilerGate.parse(note: "[spoiler] [ep:12] Big reveal", serverIsSpoiler: nil, serverThroughUnit: nil)
        #expect(parsedInline.cleanText == "Big reveal")
        #expect(parsedInline.isSpoiler)
        #expect(parsedInline.unitGate == 12)

        let gatedItem: ClubRailItem = try decode(#"""
        {
          "id": "item-1",
          "media_type": "ANIME",
          "media_id": 100,
          "sort_order": 0,
          "note": "[ep:12] Watch the ending",
          "is_spoiler": false,
          "spoiler_through_unit": null,
          "added_by": "u1",
          "title_display": "Test Anime",
          "cover_image_medium": null,
          "average_score": 85,
          "year": 2025,
          "format": "TV",
          "episode_count": 24,
          "chapter_count": null,
          "my_status": "CURRENT",
          "my_progress": 5,
          "my_rating": null,
          "member_status_counts": null,
          "member_statuses": null,
          "reactions": {},
          "my_reactions": []
        }
        """#)

        let masked = ClubSpoilerGate.maskReason(item: gatedItem, viewerStatus: "CURRENT", viewerProgress: 5, german: false)
        #expect(masked?.contains("12") == true)
        #expect(ClubSpoilerGate.maskReason(item: gatedItem, viewerStatus: "CURRENT", viewerProgress: 12, german: false) == nil)
        #expect(ClubSpoilerGate.maskReason(item: gatedItem, viewerStatus: "COMPLETED", viewerProgress: 0, german: false) == nil)

        let blanketItem: ClubRailItem = try decode(#"""
        {
          "id": "item-2",
          "media_type": "MANGA",
          "media_id": 200,
          "sort_order": 0,
          "note": "[spoiler] Final chapter panel",
          "is_spoiler": true,
          "spoiler_through_unit": null,
          "added_by": "u1",
          "title_display": "Test Manga",
          "cover_image_medium": null,
          "average_score": 88,
          "year": 2024,
          "format": "MANGA",
          "episode_count": null,
          "chapter_count": 100,
          "my_status": "CURRENT",
          "my_progress": 99,
          "my_rating": null,
          "member_status_counts": null,
          "member_statuses": null,
          "reactions": {},
          "my_reactions": []
        }
        """#)
        #expect(ClubSpoilerGate.maskReason(item: blanketItem, viewerStatus: "CURRENT", viewerProgress: 99, german: false) != nil)
        #expect(ClubSpoilerGate.maskReason(item: blanketItem, viewerStatus: "COMPLETED", viewerProgress: 99, german: false) == nil)
    }

    // MARK: - Wave 5: 09:00 confirmed day-precision manga alerts

    @Test("ReleaseNotificationPlanner schedules confirmed day-precision manga at 09:00 only when allowConfirmedDay is true")
    func confirmedDayMorningAlerts() throws {
        let gmt = try #require(TimeZone(identifier: "UTC"))
        let dayRelease = ReleaseScheduleItem(
            medium: .manga,
            mediaId: 500,
            title: "Kagurabachi",
            unitKind: .chapter,
            unitNumber: 69,
            releaseAt: Self.utc(2026, 11, 10, 0, 0),
            basis: .confirmed,
            confidence: 1.0,
            source: "mangaupdates",
            precision: .day
        )
        let key = MediaKey(kind: .manga, id: 500)

        let defaultPlan = ReleaseNotificationPlanner.plan(
            items: [dayRelease],
            following: [key],
            muted: [],
            now: Self.epoch,
            german: false,
            locale: Locale(identifier: "en_GB"),
            timeZone: gmt
        )
        #expect(defaultPlan.isEmpty)

        let optInPlan = ReleaseNotificationPlanner.plan(
            items: [dayRelease],
            following: [key],
            muted: [],
            now: Self.epoch,
            german: false,
            locale: Locale(identifier: "en_GB"),
            timeZone: gmt,
            allowConfirmedDay: true
        )
        let planned = try #require(optInPlan.first)
        #expect(planned.fireDate == Self.utc(2026, 11, 10, 9, 0))
    }

    // MARK: - Fractional chapters, volumes, and bridge start offsets

    @Test("TrackingDraft persists .5 chapters and volumesProgress through FakeLibraryBackend and ProfileStats subtracts startedAtProgress")
    func fractionalVolumesAndBridgeStats() async throws {
        let entry = LibraryEntry(
            key: MediaKey(kind: .manga, id: 901),
            rowId: 901,
            status: .current,
            progress: 12,
            createdAt: Self.epoch,
            updatedAt: Self.epoch,
            progressLabel: "12.5",
            sourceMetadata: LibrarySourceMetadata(volumesProgress: 3, repeatCount: 0, startedAtProgress: 10)
        )
        var draft = TrackingDraft(entry: entry, projectionLoaded: true)
        #expect(draft.hasHalfUnit)
        #expect(draft.volumesProgress == 3)

        draft.volumesProgress = 4
        let updatedEdit = draft.edit(maxProgress: 100)
        #expect(updatedEdit.progressLabel == .set("12.5"))
        #expect(updatedEdit.volumesProgress == .set(4))

        draft.hasHalfUnit = false
        let clearedEdit = draft.edit(maxProgress: 100)
        #expect(clearedEdit.progressLabel == .clear)

        let backend = FakeLibraryBackend()
        let user = "aaaaaaaa-1111-4111-8111-111111111111"
        backend.setRows([entry], for: user)
        let store = LibraryStore(backend: backend)
        store.bind(AccountContext(userId: user, generation: 1))
        try await store.refresh()

        let outcome = await store.apply(updatedEdit, to: entry.key)
        #expect(outcome.error == nil)
        let saved = try #require(store.entry(for: entry.key))
        #expect(saved.progressLabel == "12.5")
        #expect(saved.sourceMetadata?.volumesProgress == 4)

        let bridgeBookmarkedOnly = LibraryEntry(
            key: MediaKey(kind: .manga, id: 902),
            rowId: 902,
            status: .current,
            progress: 63,
            createdAt: Self.epoch,
            updatedAt: Self.epoch,
            sourceMetadata: LibrarySourceMetadata(startedAtProgress: 63)
        )
        let calendar = KuroLocale.calendar(locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC") ?? .current)
        let statsZero = ProfileStats.make(
            entries: [bridgeBookmarkedOnly],
            facts: [bridgeBookmarkedOnly.key: ProfileTitleFacts(title: "Source", total: 120)],
            catalogue: .loaded,
            now: Self.epoch,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        #expect(statsZero.chapters == nil)

        var readSevenMore = bridgeBookmarkedOnly
        readSevenMore.progress = 70
        let statsSeven = ProfileStats.make(
            entries: [readSevenMore],
            facts: [readSevenMore.key: ProfileTitleFacts(title: "Source", total: 120)],
            catalogue: .loaded,
            now: Self.epoch,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        #expect(statsSeven.chapters == ProfileStats.Total(units: 7, titles: 1))
    }

    @Test("Ongoing TrackingDraft allows unrestricted progress, .5 chapter, and volumes when maxProgress == 0")
    func ongoingTrackingDraftWithoutKnownTotal() {
        var draft = TrackingDraft(entry: FakeLibraryBackend.entry(.manga, 501, status: .planning, progress: 0))
        draft.status = .current
        draft.progress = 142
        draft.hasHalfUnit = true
        draft.volumesProgress = 14

        let edit = draft.edit(maxProgress: 0)
        #expect(edit.status == .set(.current))
        #expect(edit.progress == .set(142))
        #expect(edit.progressLabel == .set("142.5"))
        #expect(edit.volumesProgress == .set(14))

        var completedUnknown = TrackingDraft(entry: FakeLibraryBackend.entry(.anime, 502, status: .planning, progress: 0))
        completedUnknown.status = .completed
        let completedEdit = completedUnknown.edit(maxProgress: 0)
        #expect(completedEdit.status == .set(.completed))
        #expect(completedEdit.progress == .set(0))
    }

    @Test("CatalogStore.splitStoryTags separates safe vs spoiler tags, deduplicates, orders by rank, and drops adult tags")
    func catalogStoryTagSplit() {
        let edges: [CatalogStore.TagEdge] = [
            CatalogStore.TagEdge(
                rank: 90,
                tagId: 1,
                isSpoiler: false,
                tags: CatalogStore.TagNode(id: 1, name: "Iyashikei", category: "Theme", isAdult: false)
            ),
            CatalogStore.TagEdge(
                rank: 75,
                tagId: 2,
                isSpoiler: false,
                tags: CatalogStore.TagNode(id: 2, name: "iyashikei", category: "Theme", isAdult: false)
            ),
            CatalogStore.TagEdge(
                rank: 85,
                tagId: 3,
                isSpoiler: false,
                tags: CatalogStore.TagNode(id: 3, name: "Time Loop", category: "Plot", isAdult: false)
            ),
            CatalogStore.TagEdge(
                rank: 80,
                tagId: 4,
                isSpoiler: true,
                tags: CatalogStore.TagNode(id: 4, name: "Edge Spoiler", category: "Plot", isAdult: false)
            ),
            CatalogStore.TagEdge(
                rank: 95,
                tagId: 5,
                isSpoiler: false,
                tags: CatalogStore.TagNode(id: 5, name: "General Spoiler", category: "Plot", isAdult: false, isGeneralSpoiler: true)
            ),
            CatalogStore.TagEdge(
                rank: 70,
                tagId: 6,
                isSpoiler: false,
                tags: CatalogStore.TagNode(id: 6, name: "Media Spoiler", category: "Plot", isAdult: false, isMediaSpoiler: true)
            ),
            CatalogStore.TagEdge(
                rank: 99,
                tagId: 7,
                isSpoiler: false,
                tags: CatalogStore.TagNode(id: 7, name: "Adult Only", category: "Cast", isAdult: true)
            ),
        ]

        let split = CatalogStore.splitStoryTags(edges)
        #expect(split.safe == ["Iyashikei", "Time Loop"])
        #expect(split.spoilers == ["General Spoiler", "Edge Spoiler", "Media Spoiler"])
    }

    @Test("FriendsActivitySection.commentMaskReason gates comments by viewer progress, status, medium, and fallback scope")
    func friendsCommentSpoilerMasking() {
        let gatedEN = FriendsActivitySection.commentMaskReason(
            text: "[ep:12] Major twist",
            spoilerScope: nil,
            viewerStatus: .current,
            viewerProgress: 5,
            isManga: false,
            german: false
        )
        #expect(gatedEN.cleanText == "Major twist")
        #expect(gatedEN.mask == "Spoiler through Ep. 12 · You're at 5")

        let gatedDE = FriendsActivitySection.commentMaskReason(
            text: "[ep:12] Großer Twist",
            spoilerScope: nil,
            viewerStatus: .current,
            viewerProgress: 5,
            isManga: false,
            german: true
        )
        #expect(gatedDE.cleanText == "Großer Twist")
        #expect(gatedDE.mask == "Spoiler bis F. 12 · Du bist bei 5")

        let caughtUp = FriendsActivitySection.commentMaskReason(
            text: "[ep:12] Major twist",
            spoilerScope: nil,
            viewerStatus: .current,
            viewerProgress: 12,
            isManga: false,
            german: false
        )
        #expect(caughtUp.cleanText == "Major twist")
        #expect(caughtUp.mask == nil)

        let completed = FriendsActivitySection.commentMaskReason(
            text: "[ep:12] Major twist",
            spoilerScope: "ending",
            viewerStatus: .completed,
            viewerProgress: 0,
            isManga: false,
            german: false
        )
        #expect(completed.cleanText == "Major twist")
        #expect(completed.mask == nil)

        let mangaGated = FriendsActivitySection.commentMaskReason(
            text: "[ch:45] Final betrayal",
            spoilerScope: nil,
            viewerStatus: .current,
            viewerProgress: 10,
            isManga: true,
            german: false
        )
        #expect(mangaGated.cleanText == "Final betrayal")
        #expect(mangaGated.mask == "Spoiler through Ch. 45 · You're at 10")

        let storyFallback = FriendsActivitySection.commentMaskReason(
            text: "Plain text",
            spoilerScope: "story",
            viewerStatus: .planning,
            viewerProgress: 0,
            isManga: false,
            german: false
        )
        #expect(storyFallback.cleanText == "Plain text")
        #expect(storyFallback.mask == "Spoiler · Story")

        let endingFallback = FriendsActivitySection.commentMaskReason(
            text: "Plain ending",
            spoilerScope: "ending",
            viewerStatus: .planning,
            viewerProgress: 0,
            isManga: false,
            german: false
        )
        #expect(endingFallback.cleanText == "Plain ending")
        #expect(endingFallback.mask == "Spoiler · Ending")
    }

    @Test("Lock Screen accessory widget layout limits releases to 1 and builds content views")
    func lockScreenWidgetLayoutAndViews() {
        #expect(WidgetLayout.releaseLimit(.accessoryRectangular) == 1)
        #expect(WidgetLayout.releaseLimit(.accessoryInline) == 1)

        let base = Self.epoch
        let releases = [
            WidgetReleaseItem(
                id: "anime:1:ep:4",
                medium: .anime,
                mediaId: 1,
                title: "First Show",
                unitLabel: "Ep. 4",
                datePhrase: "Thu 20 Nov",
                line: "Ep. 4 · Thu 20 Nov",
                accessibilityLine: "Episode 4",
                basis: "confirmed",
                precision: "instant",
                countdownTarget: base.addingTimeInterval(3600),
                expiresAt: base.addingTimeInterval(7200),
                isEstimate: false,
                thumbnail: nil,
                deepLink: URL(string: "kuro://anime/1")
            ),
            WidgetReleaseItem(
                id: "manga:2:ch:18",
                medium: .manga,
                mediaId: 2,
                title: "Second Manga",
                unitLabel: "Ch. 18",
                datePhrase: "Fri 21 Nov",
                line: "Ch. 18 · Fri 21 Nov",
                accessibilityLine: "Chapter 18",
                basis: "announced",
                precision: "day",
                countdownTarget: nil,
                expiresAt: base.addingTimeInterval(86_400),
                isEstimate: false,
                thumbnail: nil,
                deepLink: URL(string: "kuro://manga/2")
            ),
        ]
        let snapshot = WidgetSnapshot(
            account: WidgetAccountHash(value: "test-account"),
            generatedAt: base,
            german: false,
            releases: releases,
            nowWatching: []
        )

        #expect(WidgetLayout.releases(snapshot, at: base, family: .accessoryRectangular).count == 1)
        #expect(WidgetLayout.releases(snapshot, at: base, family: .accessoryInline).count == 1)
        _ = NextReleaseWidgetContent(snapshot: snapshot, date: base, family: .accessoryRectangular, german: false)
        _ = NextReleaseWidgetContent(snapshot: snapshot, date: base, family: .accessoryInline, german: false)
    }

    @Test("ProviderAvailabilityStore.normalizedAudioLanguageCode maps ISO and regional language strings")
    func normalizedAudioLanguageCodes() {
        #expect(ProviderAvailabilityStore.normalizedAudioLanguageCode("JP") == "ja")
        #expect(ProviderAvailabilityStore.normalizedAudioLanguageCode("japanese") == "ja")
        #expect(ProviderAvailabilityStore.normalizedAudioLanguageCode("KR") == "ko")
        #expect(ProviderAvailabilityStore.normalizedAudioLanguageCode("korean") == "ko")
        #expect(ProviderAvailabilityStore.normalizedAudioLanguageCode("CN") == "zh")
        #expect(ProviderAvailabilityStore.normalizedAudioLanguageCode("GER") == "de")
        #expect(ProviderAvailabilityStore.normalizedAudioLanguageCode("english") == "en")
        #expect(ProviderAvailabilityStore.normalizedAudioLanguageCode("") == nil)
        #expect(ProviderAvailabilityStore.normalizedAudioLanguageCode(nil) == nil)
    }

    @Test("DetailSourceCard.parsedChapterNumber extracts EN and DE adaptation chapter handoff numbers")
    func adaptationBridgeChapterParsing() {
        #expect(DetailSourceCard.parsedChapterNumber(from: "Ch. 64") == 64)
        #expect(DetailSourceCard.parsedChapterNumber(from: "Chapter 112") == 112)
        #expect(DetailSourceCard.parsedChapterNumber(from: "Kap. 38") == 38)
        #expect(DetailSourceCard.parsedChapterNumber(from: "Kapitel 14") == 14)
        #expect(DetailSourceCard.parsedChapterNumber(from: "Vol. 8") == nil)
    }

    @Test("ProviderAvailabilityStore honors account-scoped sub vs dub preference in watch link resolution")
    func subDubAudioVariantPreference() async throws {
        let defaults = try TestDefaults()
        let server = StubServer()
        server.respond { request in
            switch request.resource {
            case "external_links":
                return .json("""
                    [{"id":1,"media_type":"ANIME","media_id":42,"site":"Crunchyroll","url":"https://www.crunchyroll.com/series/test","language":"en","color":null,"priority":1,"is_disabled":false,"created_at":"\(ListRowJSON.createdAt)","updated_at":"\(ListRowJSON.updatedAt)"}]
                    """)
            case "rpc/get_media_availability_status":
                return .json(#"[{"has_rows":true,"status":"ready","last_refreshed_at":"\#(ListRowJSON.createdAt)","next_refresh_at":null,"stale_days":1}]"#)
            case "rpc/batch_provider_availability_for_media_v2":
                return .json("""
                    [{"media_type":"ANIME","media_id":42,"providers":[{"slug":"crunchyroll","display_name":"Crunchyroll","url":null,"languages":["ja","en"],"audio_languages":["ja","en"],"subtitle_languages":["en"],"countries_by_audio_lang":{"ja":["US"],"en":["US"]},"countries_by_sub_lang":{"en":["US"]},"is_stale":false}]}]
                    """)
            default:
                return .emptyArray
            }
        }

        let flags = FeatureFlags(userDefaults: defaults.defaults, launchArguments: ["--ff-on=streaming_availability_v1"])
        let graph = AppComposition.testingGraph(
            testingUserDefaults: defaults.defaults,
            notificationCenter: FakeNotificationCenter(),
            client: StubSupabase.makeClient(server: server),
            flags: flags
        )
        let userId = "bbbbbbbb-2222-4222-8222-222222222222"
        await graph.session.applySession(userId: userId, email: "\(userId)@example.com")
        await graph.libraryActions.libraryRefreshTask?.value
        defer {
            defaults.tearDown()
            server.shutDown()
        }

        graph.releases.setPreferredAudioVariant("sub")
        let subSnap = try #require(await graph.availability.resolveWatchLinks(animeId: 42, originalLanguage: "JP", progress: 0, locale: "en_US"))
        #expect(subSnap.all.count == 1)
        let subAvailabilityReq = server.requests.last(where: { $0.resource == "rpc/batch_provider_availability_for_media_v2" })
        let subBody = String(data: subAvailabilityReq?.body ?? Data(), encoding: .utf8) ?? ""
        #expect(subBody.contains("ja"))

        graph.releases.setPreferredAudioVariant("dub")
        let dubSnap = try #require(await graph.availability.resolveWatchLinks(animeId: 42, originalLanguage: "JP", progress: 0, locale: "en_US"))
        #expect(dubSnap.all.count == 1)
        let dubAvailabilityReq = server.requests.last(where: { $0.resource == "rpc/batch_provider_availability_for_media_v2" })
        let dubBody = String(data: dubAvailabilityReq?.body ?? Data(), encoding: .utf8) ?? ""
        #expect(dubBody.contains("en"))

        await graph.session.endSession()
    }
}
