//
//  DataLaneTests.swift
//  KuroTests
//
//  Data-delivery lane (overnight 2026-11-01): the explicit catalog projections (no internal
//  `safety_*` / `synopsis_enhanced_*` column ever selected, every decoder field kept), the card
//  projection of "More like this" (never served as a detail model, no per-id N+1), the cached
//  external links, the size-aware image cache keys, the friend-count freshness rule and the parallel
//  combined search. Pure helpers are tested directly; owner behaviour runs the real owners over the
//  real supabase-swift client answered in-process (StubPostgREST, no network).
//

import Testing
import Foundation
import KuroCore
import Synchronization
@testable import Kuro

// MARK: - Column lists (pure)

@MainActor
@Suite("Data lane: catalog column lists")
struct CatalogColumnListTests {

    @Test("No column list selects internal moderation or pipeline state")
    func noInternalColumns() {
        for (name, columns) in CatalogColumns.allColumnLists {
            #expect(!columns.isEmpty, "\(name)")
            for column in columns {
                #expect(!CatalogColumns.isInternalColumn(column), "\(name) selects \(column)")
                #expect(!column.hasPrefix("safety_"), "\(name) selects \(column)")
            }
            #expect(Set(columns).count == columns.count, "\(name) repeats a column")
        }
        for embed in [CatalogColumns.characterEmbed, CatalogColumns.staffEmbed, CatalogColumns.authorEmbed] {
            #expect(!embed.contains("description"), "\(embed)")
        }
    }

    @Test("The internal-column guard: safety_* and synopsis_enhanced_* (but the state gate) and description_normalized")
    func internalColumnGuard() {
        for hidden in ["safety_state", "safety_model_rationale", "safety_last_error", "synopsis_enhanced_last_error",
                         "synopsis_enhanced_source", "synopsis_enhanced_model", "synopsis_enhanced_retry_count",
                         "description_normalized", " safety_blocked "] {
            #expect(CatalogColumns.isInternalColumn(hidden), "\(hidden)")
        }
        for allowed in ["synopsis_enhanced", "synopsis_enhanced_state", "description", "id", "is_adult", "genres"] {
            #expect(!CatalogColumns.isInternalColumn(allowed), "\(allowed)")
        }
    }

    @Test("Detail lists keep every decoder field except the omitted internal ones")
    func detailListsCoverDecoders() {
        let animeKeys = Set(Anime.CodingKeys.allCases.map(\.rawValue))
        let mangaKeys = Set(Manga.CodingKeys.allCases.map(\.rawValue))
        #expect(Set(CatalogColumns.animeDetail) == animeKeys.subtracting(CatalogColumns.omittedDetailColumns))
        #expect(Set(CatalogColumns.mangaDetail) == mangaKeys.subtracting(CatalogColumns.omittedDetailColumns))
        for kept in ["synopsis_enhanced", "synopsis_enhanced_state", "description", "country_of_origin", "next_airing_at"] {
            #expect(CatalogColumns.animeDetail.contains(kept), "\(kept)")
        }
        // Every omitted column really is internal.
        #expect(CatalogColumns.omittedDetailColumns.allSatisfy(CatalogColumns.isInternalColumn))
    }

    @Test("Card projections carry the decoders' required fields and what the similar cards read")
    func cardProjectionsDecode() {
        for required in ["id", "is_adult", "created_at", "updated_at", "genres", "cover_image_large", "title_english"] {
            #expect(CatalogColumns.animeCard.contains(required), "anime \(required)")
            #expect(CatalogColumns.mangaCard.contains(required), "manga \(required)")
        }
        #expect(CatalogColumns.animeCard.contains("episodes"))
        #expect(CatalogColumns.animeCard.contains("next_episode_number"))
        #expect(CatalogColumns.mangaCard.contains("chapters"))
        // A card is never a detail: no synopsis.
        #expect(!CatalogColumns.animeCard.contains("description"))
        #expect(!CatalogColumns.mangaCard.contains("description"))
    }

    @Test("Units drop the long description; the stream link reads two columns; links read every decoded column")
    func unitAndLinkLists() {
        #expect(!CatalogColumns.episodeList.contains("description"))
        #expect(!CatalogColumns.chapterList.contains("description"))
        #expect(Set(CatalogColumns.episodeList) == Set(Episode.CodingKeys.allCases.map(\.rawValue)).subtracting(["description"]))
        #expect(Set(CatalogColumns.chapterList) == Set(MangaChapter.CodingKeys.allCases.map(\.rawValue)).subtracting(["description"]))
        #expect(CatalogColumns.select(CatalogColumns.episodeStreamLink) == "stream_url,stream_site")
        #expect(Set(CatalogColumns.externalLinks) == Set(ExternalLink.CodingKeys.allCases.map(\.rawValue)))
    }

    @Test("Batch helpers: missing ids de-duplicated in order; chunks of at most 100")
    func batchHelpers() {
        #expect(CatalogStore.uniqueMissingIds([5, 3, 5, 9, 3, 1], resolved: [9]) == [5, 3, 1])
        #expect(CatalogStore.batchChunks([]).isEmpty)
        let chunks = CatalogStore.batchChunks(Array(1...250))
        #expect(chunks.map(\.count) == [100, 100, 50])
        #expect(chunks.flatMap { $0 } == Array(1...250))
        #expect(CatalogStore.externalLinksKey(mediaType: "anime", mediaId: 7) == "ANIME-7")
        #expect(CatalogStore.externalLinksKey(mediaType: "MANGA", mediaId: 7) != CatalogStore.externalLinksKey(mediaType: "ANIME", mediaId: 7))
    }
}

// MARK: - Image cache keys (pure)

@Suite("Data lane: image pipeline cache keys")
struct ImagePipelineKeyTests {
    let url = URL(fileURLWithPath: "/img/cover/1.jpg")

    @Test("Requested sizes clamp to [180, 1200] and round up to a bucket; nil stays full")
    func buckets() {
        #expect(ImagePipeline.pixelBucket(for: nil) == nil)
        #expect(ImagePipeline.pixelBucket(for: 1) == 180)
        #expect(ImagePipeline.pixelBucket(for: 180) == 180)
        #expect(ImagePipeline.pixelBucket(for: 181) == 240)
        #expect(ImagePipeline.pixelBucket(for: 360) == 360)
        #expect(ImagePipeline.pixelBucket(for: 900) == 900)
        #expect(ImagePipeline.pixelBucket(for: 901) == 1200)
        #expect(ImagePipeline.pixelBucket(for: 4_200) == 1200)
        #expect(ImagePipeline.pixelBucket(for: ImagePipeline.defaultPrefetchPixelSize) == 900)
        #expect(ImagePipeline.pixelBuckets == ImagePipeline.pixelBuckets.sorted())
        #expect(ImagePipeline.pixelBuckets.last == ImagePipeline.maxDecodePixelSize)
    }

    @Test("The key carries the decode size: a thumbnail and a hero of one URL never share an entry")
    func keysCarrySize() {
        let thumb = ImagePipeline.cacheKey(url: url, bucket: 180)
        let hero = ImagePipeline.cacheKey(url: url, bucket: 1200)
        let full = ImagePipeline.cacheKey(url: url, bucket: nil)
        #expect(Set([thumb, hero, full]).count == 3)
        #expect(thumb.hasPrefix(url.absoluteString))
        #expect(full.hasSuffix("#full"))
    }

    @Test("A request is served by its own bucket, a larger one or the full image, never a smaller one")
    func servingKeysNeverDownsize() {
        let serving = ImagePipeline.servingKeys(url: url, bucket: 640)
        #expect(serving.first == ImagePipeline.cacheKey(url: url, bucket: 640))
        #expect(serving.contains(ImagePipeline.cacheKey(url: url, bucket: 900)))
        #expect(serving.contains(ImagePipeline.cacheKey(url: url, bucket: 1200)))
        #expect(serving.last == ImagePipeline.cacheKey(url: url, bucket: nil))
        for smaller in [180, 240, 360, 480] {
            #expect(!serving.contains(ImagePipeline.cacheKey(url: url, bucket: smaller)), "\(smaller)")
        }
        #expect(ImagePipeline.servingKeys(url: url, bucket: nil) == [ImagePipeline.cacheKey(url: url, bucket: nil)])
    }

    @Test("A decode smaller than its bucket is the full image and is stored as full")
    func storageBucket() {
        #expect(ImagePipeline.storageBucket(requested: 900, decodedLongestSide: 650) == nil)
        #expect(ImagePipeline.storageBucket(requested: 900, decodedLongestSide: 900) == 900)
        #expect(ImagePipeline.storageBucket(requested: 480, decodedLongestSide: 480) == 480)
        #expect(ImagePipeline.storageBucket(requested: nil, decodedLongestSide: 3_000) == nil)
    }
}

// MARK: - Friend-count freshness and availability rules (pure)

@MainActor
@Suite("Data lane: friend-count and availability rules")
struct DataLaneRuleTests {

    @Test("Friend counts: fresh and in-flight keys are skipped; duplicates collapse; stale keys are asked again")
    func friendCountKeys() {
        let now = Date(timeIntervalSince1970: 10_000)
        let keys = ["ANIME-1", "ANIME-2", "ANIME-1", "MANGA-1", "ANIME-3", "ANIME-4"]
        let pending = SocialActivityStore.friendCountKeysToRequest(
            keys,
            fetchedAt: ["ANIME-2": now.addingTimeInterval(-30), "ANIME-4": now.addingTimeInterval(-500)],
            inFlight: ["ANIME-3"],
            now: now,
            ttl: SocialActivityStore.friendCountTTL
        )
        #expect(pending == ["ANIME-1", "MANGA-1", "ANIME-4"])
        #expect(SocialActivityStore.friendCountKey(mediaType: "ANIME", mediaId: 9) == "ANIME-9")
    }

    @Test("Availability refresh is queued for no status, no rows or rows 30+ days old")
    func availabilityQueueRule() throws {
        func status(_ json: String) throws -> MediaAvailabilityStatus {
            try JSONDecoder().decode(MediaAvailabilityStatus.self, from: Data(json.utf8))
        }
        let missing = try status(#"{"has_rows":false,"status":"missing","last_refreshed_at":null,"next_refresh_at":null,"stale_days":null}"#)
        let stale = try status(#"{"has_rows":true,"status":"ready","last_refreshed_at":null,"next_refresh_at":null,"stale_days":30}"#)
        let fresh = try status(#"{"has_rows":true,"status":"ready","last_refreshed_at":null,"next_refresh_at":null,"stale_days":2}"#)
        #expect(ProviderAvailabilityStore.shouldQueueAvailabilityRefresh(nil))
        #expect(ProviderAvailabilityStore.shouldQueueAvailabilityRefresh(missing))
        #expect(ProviderAvailabilityStore.shouldQueueAvailabilityRefresh(stale))
        #expect(!ProviderAvailabilityStore.shouldQueueAvailabilityRefresh(fresh))
        #expect(ProviderAvailabilityStore.availabilityKey(mediaType: "anime", mediaId: 42) == "ANIME-42")
    }
}

// MARK: - Owner behaviour over the stub server

@MainActor
@Suite("Data lane: catalog, links and search requests", .timeLimit(.minutes(1)))
struct DataLaneRequestTests {

    nonisolated static func selected(_ request: RecordedRequest) -> [String] {
        (request.query("select") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    @Test("Detail by id names its columns: no select=*, no internal column, every detail field")
    func detailReadNamesColumns() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "anime": return .json("[" + PublicRowJSON.anime(990_205, title: "Anime 990205") + "]")
            case "manga": return .json("[" + PublicRowJSON.manga(990_206, title: "Manga 990206") + "]")
            default: return .emptyArray
            }
        }
        let catalog = harness.service.catalog
        #expect(try await catalog.fetchAnimeById(990_205)?.title == "Anime 990205")
        #expect(try await catalog.fetchMangaById(990_206)?.title == "Manga 990206")

        let anime = try #require(harness.requests(to: "anime").first)
        let manga = try #require(harness.requests(to: "manga").first)
        #expect(anime.query("select") != "*")
        #expect(Self.selected(anime) == CatalogColumns.animeDetail)
        #expect(Self.selected(manga) == CatalogColumns.mangaDetail)
        #expect(Self.selected(anime).allSatisfy { !CatalogColumns.isInternalColumn($0) })
        await harness.tearDown()
    }

    @Test("Similar hydration: one card-projection batch, no per-id retry for ids the batch left out, and never a detail model")
    func similarHydrationUsesCardsWithoutNPlusOne() async throws {
        let harness = try PublicDataHarness { request in
            guard request.resource == "anime" else { return .emptyArray }
            if request.query("id")?.hasPrefix("in.") == true {
                // 3 of 4 ids come back; 990304 is missing or adult-filtered on the server.
                return .json("[" + [990_301, 990_302, 990_303].map { PublicRowJSON.anime($0, title: "Card \($0)") }.joined(separator: ",") + "]")
            }
            return .json("[" + PublicRowJSON.anime(990_302, title: "Full 990302") + "]")
        }
        let catalog = harness.service.catalog

        let cards = try #require(await catalog.fetchAnimeByIdsPreservingOrder([990_303, 990_304, 990_301, 990_302, 990_303]))
        #expect(cards.map(\.id) == [990_303, 990_301, 990_302, 990_303])
        let reads = harness.requests(to: "anime")
        #expect(reads.count == 1, "no N+1 for the unresolved id: \(reads)")
        #expect(Self.selected(try #require(reads.first)) == CatalogColumns.animeCard)
        #expect(catalog.animeDetailCache.isEmpty, "a card row must never become a detail model")

        // Again: served from the card cache, no request.
        _ = await catalog.fetchAnimeByIdsPreservingOrder([990_301, 990_302])
        #expect(harness.requests(to: "anime").count == 1)

        // Opening one of them loads the full detail model by id.
        #expect(try await catalog.fetchAnimeById(990_302)?.title == "Full 990302")
        let detail = try #require(harness.requests(to: "anime").last)
        #expect(detail.query("id") == "eq.990302")
        #expect(Self.selected(detail) == CatalogColumns.animeDetail)
        await harness.tearDown()
    }

    @Test("Credits are bounded and fetch no entity description")
    func creditsAreBounded() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "anime_characters" ? .json("[" + PublicRowJSON.character(1, name: "Hero") + "]") : .emptyArray
        }
        let catalog = harness.service.catalog
        #expect(await catalog.fetchCharactersForAnime(animeId: 9).count == 1)
        _ = await catalog.fetchStaffForAnime(animeId: 9)
        _ = await catalog.fetchAuthorsForManga(mangaId: 9)
        for resource in ["anime_characters", "anime_staff", "manga_authors"] {
            let request = try #require(harness.requests(to: resource).first, "\(resource)")
            #expect(request.query("limit") == "\(CatalogColumns.creditsRowLimit)", "\(resource)")
            #expect(!(request.query("select") ?? "").contains("description"), "\(resource)")
        }
        await harness.tearDown()
    }

    @Test("External links are read once per media within the TTL; a failed read is not cached")
    func externalLinksAreCached() async throws {
        let fail = Mutex(true)
        let harness = try PublicDataHarness { request in
            guard request.resource == "external_links" else { return .emptyArray }
            if fail.withLock({ $0 }) { return .json(#"{"code":"PGRST100","details":null,"hint":null,"message":"boom"}"#, status: 400) }
            return .json("""
                [{"id":1,"media_type":"ANIME","media_id":42,"site":"Crunchyroll","url":"https://www.crunchyroll.com/x",
                  "language":"en","color":null,"priority":1,"is_disabled":false,
                  "created_at":"2026-01-01T00:00:00+00:00","updated_at":"2026-01-01T00:00:00+00:00"}]
                """)
        }
        let catalog = harness.service.catalog
        #expect(await catalog.fetchExternalLinks(mediaType: "ANIME", mediaId: 42).isEmpty)
        fail.withLock { $0 = false }
        #expect(await catalog.fetchExternalLinks(mediaType: "ANIME", mediaId: 42).count == 1)
        #expect(await catalog.fetchExternalLinks(mediaType: "anime", mediaId: 42).count == 1)
        // A manga with the same id is its own entry.
        _ = await catalog.fetchExternalLinks(mediaType: "MANGA", mediaId: 42)

        let reads = harness.requests(to: "external_links")
        #expect(reads.count == 3, "failed read, first good read, the manga read: \(reads)")
        #expect(Set(Self.selected(try #require(reads.first))) == Set(CatalogColumns.externalLinks))
        await harness.tearDown()
    }

    @Test("Combined search sends the anime and manga pages together and publishes both")
    func combinedSearchRunsBothPages() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/search_anime_page", "rpc/search_manga_page": return PublicRowJSON.cards([1, 2])
            default: return .emptyArray
            }
        }
        let search = harness.service.search
        search.resetCombinedSearch(query: "naruto")
        await search.fetchNextSearchPage()
        #expect(search.searchAnimeItems.map(\.id) == [1, 2])
        #expect(search.searchMangaItems.map(\.id) == [1, 2])
        #expect(!search.hasMoreSearch)
        #expect(search.errorMessage == nil)
        #expect(harness.requests(to: "rpc/search_anime_page").count == 1)
        #expect(harness.requests(to: "rpc/search_manga_page").count == 1)
        await harness.tearDown()
    }

    @Test("Combined search: a failed side ends paging with a message; the other side's rows are kept")
    func combinedSearchFailure() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/search_anime_page": return PublicRowJSON.cards(Array(1...20))
            case "rpc/search_manga_page": return .json(#"{"code":"PGRST100","details":null,"hint":null,"message":"boom"}"#, status: 400)
            default: return .emptyArray
            }
        }
        let search = harness.service.search
        search.resetCombinedSearch(query: "naruto")
        await search.fetchNextSearchPage()
        #expect(search.searchAnimeItems.count == 20)
        #expect(search.searchMangaItems.isEmpty)
        #expect(!search.hasMoreSearch)
        #expect(search.errorMessage != nil)
        await harness.tearDown()
    }
}

@MainActor
@Suite("Data lane: friend counts", .timeLimit(.minutes(1)))
struct DataLaneFriendCountTests {

    @Test("A fresh count is not requested again; prefetches of two screens both land")
    func freshCountsAreReused() async throws {
        let harness = try PublicDataHarness { request in
            guard request.resource == "rpc/count_friends_tracking" else { return .emptyArray }
            let items = request.jsonObject?["p_items"] as? String ?? ""
            var rows: [String] = []
            if items.contains(#""101""#) { rows.append(#"{"media_type":"ANIME","media_id":101,"count":3}"#) }
            if items.contains(#""202""#) { rows.append(#"{"media_type":"ANIME","media_id":202,"count":1}"#) }
            return .json("[" + rows.joined(separator: ",") + "]")
        }
        let service = harness.service
        let social = service.social
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")

        social.prefetchFriendCounts(items: [(mediaType: "ANIME", mediaId: 101)])
        let first = try #require(social.friendCountPrefetchTask)
        // A second screen starts before the first finished: it no longer cancels the first.
        social.prefetchFriendCounts(items: [(mediaType: "ANIME", mediaId: 202), (mediaType: "ANIME", mediaId: 101)])
        let second = try #require(social.friendCountPrefetchTask)
        await first.value
        await second.value
        #expect(!first.isCancelled)
        #expect(social.friendCount(mediaId: 101, mediaType: "ANIME") == 3)
        #expect(social.friendCount(mediaId: 202, mediaType: "ANIME") == 1)
        let requests = harness.requests(to: "rpc/count_friends_tracking")
        #expect(requests.count == 2)
        // The second request asked only for the key the first was not already fetching.
        let bodies = requests.map { $0.jsonObject?["p_items"] as? String ?? "" }
        #expect(bodies.filter { $0.contains(#""101""#) }.count == 1, "\(bodies)")
        #expect(bodies.filter { $0.contains(#""202""#) }.count == 1, "\(bodies)")

        // Both fresh: no request at all.
        social.prefetchFriendCounts(items: [(mediaType: "ANIME", mediaId: 101), (mediaType: "ANIME", mediaId: 202)])
        #expect(harness.requests(to: "rpc/count_friends_tracking").count == 2)
        await harness.tearDown()
    }
}
