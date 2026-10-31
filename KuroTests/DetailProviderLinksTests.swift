//
//  DetailProviderLinksTests.swift
//  KuroTests
//
//  The detail pages' watch/read link resolution, owned by ProviderAvailabilityStore
//  (ProviderAvailabilityStore+DetailLinks.swift) since the E5 detail-page decomposition: the real owner
//  over the real supabase-swift client answered in-process (StubPostgREST, no network), with
//  `streaming_availability_v1` on or off through the injected flags. Covers the verified-vs-catalog
//  fallback, the flag-off path, the refresh-requested server write, the progress-keyed primary, the
//  superseded (cancelled) resolution and the single outbound-URL scheme allowlist. The pure item
//  builders keep their own tests (DetailTruthfulnessTests, KuroTests.swift).
//

import Testing
import Foundation
import KuroCore
import Synchronization
@testable import Kuro

/// A graph whose SDK client talks to a stub server, with `streaming_availability_v1` forced on or off.
@MainActor
private struct DetailLinksHarness {
    let server: StubServer
    let service: AppGraph
    let defaults: TestDefaults

    init(streamingAvailability: Bool, responder: @escaping StubServer.Responder) throws {
        defaults = try TestDefaults()
        server = StubServer()
        server.respond(with: responder)
        let flag = "streaming_availability_v1"
        let flags = FeatureFlags(
            userDefaults: defaults.defaults,
            launchArguments: [streamingAvailability ? "--ff-on=\(flag)" : "--ff-off=\(flag)"]
        )
        service = AppComposition.testingGraph(
            testingUserDefaults: defaults.defaults,
            notificationCenter: FakeNotificationCenter(),
            client: StubSupabase.makeClient(server: server),
            flags: flags
        )
    }

    var availability: ProviderAvailabilityStore { service.availability }

    func requests(to resource: String) -> [RecordedRequest] {
        server.requests.filter { $0.resource == resource }
    }

    /// Requests to the availability RPCs (status, provider v2, refresh enqueue).
    var availabilityRPCs: [RecordedRequest] {
        server.requests.filter { ($0.resource ?? "").hasPrefix("rpc/") }
    }

    func tearDown() async {
        await service.session.endSession()
        defaults.tearDown()
        server.shutDown()
    }
}

@MainActor
@Suite("Detail pages: provider links (ProviderAvailability owner)", .timeLimit(.minutes(1)))
struct DetailProviderLinksTests {
    nonisolated static let animeId = 42
    nonisolated static let mangaId = 77
    nonisolated static let crunchyrollURL = "https://www.crunchyroll.com/series/test"
    nonisolated static let netflixURL = "https://www.netflix.com/title/1"

    // MARK: Fixtures

    nonisolated static func externalLinks(_ links: [(id: Int, site: String, url: String)], mediaType: String, mediaId: Int) -> StubResponse {
        let rows: [[String: Any]] = links.enumerated().map { index, link in
            [
                "id": link.id, "media_type": mediaType, "media_id": mediaId, "site": link.site, "url": link.url,
                "language": "en", "color": NSNull(), "priority": index + 1, "is_disabled": false,
                "created_at": ListRowJSON.createdAt, "updated_at": ListRowJSON.updatedAt,
            ]
        }
        return ListRowJSON.response(rows)
    }

    nonisolated static func providerBatch(mediaType: String, mediaId: Int, url: String?, isStale: Bool) -> StubResponse {
        let urlJSON = url.map { "\"\($0)\"" } ?? "null"
        return .json("""
            [{"media_type":"\(mediaType)","media_id":\(mediaId),"providers":[{"slug":"crunchyroll","display_name":"Crunchyroll",
              "url":\(urlJSON),"languages":["ja","en"],"audio_languages":["ja","en"],"subtitle_languages":["en","de"],
              "countries_by_audio_lang":{"en":["US"]},"countries_by_sub_lang":{"de":["DE"]},"is_stale":\(isStale)}]}]
            """)
    }

    /// Refreshed recently: no refresh is enqueued.
    nonisolated static let freshStatus = StubResponse.json(
        #"[{"has_rows":true,"status":"ready","last_refreshed_at":"\#(ListRowJSON.createdAt)","next_refresh_at":null,"stale_days":1}]"#)
    /// Never refreshed: a refresh is enqueued.
    nonisolated static let missingStatus = StubResponse.json(
        #"[{"has_rows":false,"status":"missing","last_refreshed_at":null,"next_refresh_at":null,"stale_days":null}]"#)

    nonisolated static func episode(number: Int, site: String, url: String) -> StubResponse {
        .json("""
            [{"id":9,"anime_id":\(animeId),"number":\(number),"title":null,"title_romaji":null,"description":null,
              "air_date":null,"air_at":null,"thumbnail":null,"duration":null,"is_filler":false,"is_recap":false,
              "is_mixed":false,"filler_source":null,"stream_url":"\(url)","stream_site":"\(site)",
              "created_at":"\(ListRowJSON.createdAt)","updated_at":"\(ListRowJSON.updatedAt)"}]
            """)
    }

    nonisolated static let animeCatalog = externalLinks(
        [(id: 1, site: "Crunchyroll", url: crunchyrollURL), (id: 2, site: "Netflix", url: netflixURL)],
        mediaType: "ANIME", mediaId: animeId)

    // MARK: Verified vs catalog fallback

    @Test("Verified providers replace the catalog list; with no fresh verified provider the catalog list is the fallback", arguments: [false, true])
    func verifiedVersusCatalogFallback(verifiedIsStale: Bool) async throws {
        let harness = try DetailLinksHarness(streamingAvailability: true) { request in
            switch request.resource {
            case "external_links": return Self.animeCatalog
            case "rpc/get_media_availability_status": return Self.freshStatus
            case "rpc/batch_provider_availability_for_media_v2":
                // No provider URL: the verified item resolves its link from the matching catalog link.
                return Self.providerBatch(mediaType: "ANIME", mediaId: Self.animeId, url: nil, isStale: verifiedIsStale)
            default: return .emptyArray
            }
        }
        let snapshot = try #require(await harness.availability.resolveWatchLinks(
            animeId: Self.animeId, originalLanguage: "ja", progress: nil, locale: "en_US"))

        if verifiedIsStale {
            #expect(snapshot.all.map(\.title) == ["Crunchyroll", "Netflix"])
            #expect(snapshot.all.allSatisfy { !$0.isVerified })
            #expect(snapshot.all.map(\.subtitle) == Array(repeating: "Catalog link only. Availability may vary by region.", count: 2))
            #expect(snapshot.note == "Catalog links only. Verified availability is still being refreshed.")
            #expect(snapshot.statusCaption?.hasPrefix("Last checked ") == true, "\(String(describing: snapshot.statusCaption))")
        } else {
            #expect(snapshot.all.map(\.title) == ["Crunchyroll"])
            #expect(snapshot.all.allSatisfy { $0.isVerified })
            #expect(snapshot.all.first?.url == Self.crunchyrollURL)
            let typedNote = harness.availability.bestProviderAvailabilityNote(
                mediaId: Self.animeId, mediaType: "ANIME", preferredAudioLang: "en",
                preferredSubtitleLang: "en", originalLanguage: "ja")?.displayText
            #expect(typedNote != nil)
            #expect(snapshot.note == typedNote)
            #expect(snapshot.statusCaption?.hasPrefix("Verified ") == true, "\(String(describing: snapshot.statusCaption))")
        }
        #expect(snapshot.primary == snapshot.all.first)
        // Fresh status: no refresh was enqueued.
        #expect(harness.requests(to: "rpc/enqueue_media_availability_refresh").isEmpty)
        await harness.tearDown()
    }

    // MARK: Flag off

    @Test("streaming_availability_v1 off: no availability request, catalog links only, the page's region note, no caption (watch and read)")
    func flagOffUsesCatalogOnly() async throws {
        let harness = try DetailLinksHarness(streamingAvailability: false) { request in
            guard request.resource == "external_links" else { return .emptyArray }
            if request.query("media_type") == "eq.MANGA" {
                return Self.externalLinks(
                    [(id: 3, site: "VIZ", url: "https://www.viz.com/x"), (id: 4, site: "MANGA Plus", url: "https://mangaplus.shueisha.co.jp/x")],
                    mediaType: "MANGA", mediaId: Self.mangaId)
            }
            return Self.animeCatalog
        }
        let watch = try #require(await harness.availability.resolveWatchLinks(
            animeId: Self.animeId, originalLanguage: "ja", progress: 2, locale: "en_US"))
        let read = try #require(await harness.availability.resolveReadLinks(mangaId: Self.mangaId, locale: "en_US"))

        #expect(harness.availabilityRPCs.isEmpty, "\(harness.availabilityRPCs)")
        #expect(watch.all.map(\.title) == ["Crunchyroll", "Netflix"])
        #expect(watch.all.allSatisfy { !$0.isVerified })
        #expect(watch.note == "Availability, audio, and subtitle options may vary by region.")
        #expect(watch.statusCaption == nil)
        // Manga ranking: MANGA Plus before VIZ; the primary is the first item.
        #expect(read.all.map(\.title) == ["MANGA Plus", "VIZ"])
        #expect(read.all.allSatisfy { !$0.isVerified })
        #expect(read.all.first?.subtitle == "Catalog link only. Reading rights may vary by region and publisher.")
        #expect(read.primary == read.all.first)
        #expect(read.note == "Reading availability may vary by region and publisher.")
        #expect(read.statusCaption == nil)
        await harness.tearDown()
    }

    // MARK: Refresh requested

    @Test("Refresh requested: the enqueue server write happens once (status re-read, caption says refreshing); a second resolution inside the cooldown writes nothing")
    func refreshRequestedWritesOnce() async throws {
        let harness = try DetailLinksHarness(streamingAvailability: true) { request in
            switch request.resource {
            case "external_links":
                return Self.externalLinks([(id: 3, site: "VIZ", url: "https://www.viz.com/x")], mediaType: "MANGA", mediaId: Self.mangaId)
            case "rpc/get_media_availability_status": return Self.missingStatus
            case "rpc/enqueue_media_availability_refresh": return .json("true")
            default: return .emptyArray
            }
        }
        let first = try #require(await harness.availability.resolveReadLinks(mangaId: Self.mangaId, locale: "en_US"))

        let writes = harness.requests(to: "rpc/enqueue_media_availability_refresh")
        #expect(writes.count == 1, "\(writes)")
        let write = try #require(writes.first)
        #expect(write.jsonObject?["p_media_type"] as? String == "MANGA")
        #expect(write.jsonObject?["p_media_id"] as? Int == Self.mangaId)
        #expect(write.jsonObject?["p_reason"] as? String == "detail_open")
        // Status read before, inside the enqueue decision, and re-read after the refresh was requested.
        #expect(harness.requests(to: "rpc/get_media_availability_status").count == 3)
        #expect(harness.requests(to: "rpc/batch_provider_availability_for_media_v2").count == 1)
        #expect(first.statusCaption == "Refreshing verified availability now.")
        #expect(first.note == "Catalog links only. Verified availability is still being refreshed.")
        #expect(first.all.map(\.title) == ["VIZ"])

        // Inside the 10-minute cooldown: no second write.
        let second = try #require(await harness.availability.resolveReadLinks(mangaId: Self.mangaId, locale: "en_US"))
        #expect(harness.requests(to: "rpc/enqueue_media_availability_refresh").count == 1)
        #expect(second.statusCaption == nil)
        await harness.tearDown()
    }

    // MARK: Keys

    @Test("Anime is keyed on progress: the primary is the provider of episode progress + 1, not the first item")
    func primaryFollowsNextEpisodeSite() async throws {
        let harness = try DetailLinksHarness(streamingAvailability: false) { request in
            switch request.resource {
            case "external_links": return Self.animeCatalog
            case "episodes":
                return request.query("number") == "eq.4"
                    ? Self.episode(number: 4, site: "Netflix", url: Self.netflixURL)
                    : .emptyArray
            default: return .emptyArray
            }
        }
        let atThree = try #require(await harness.availability.resolveWatchLinks(
            animeId: Self.animeId, originalLanguage: nil, progress: 3, locale: "en_US"))
        #expect(atThree.all.map(\.title) == ["Crunchyroll", "Netflix"])
        #expect(atThree.primary?.title == "Netflix")

        let unwatched = try #require(await harness.availability.resolveWatchLinks(
            animeId: Self.animeId, originalLanguage: nil, progress: nil, locale: "en_US"))
        #expect(unwatched.primary?.title == "Crunchyroll")
        #expect(harness.requests(to: "episodes").map { $0.query("number") } == ["eq.4", "eq.1"])
        await harness.tearDown()
    }

    // MARK: Supersession

    @Test("A superseded (cancelled) resolution returns nil, so the page never publishes it over the newer run's links")
    func supersededResolutionDoesNotPublish() async throws {
        let slow = StubGate()
        let episodeReads = Mutex(0)
        let harness = try DetailLinksHarness(streamingAvailability: false) { request in
            switch request.resource {
            case "episodes":
                // The first run's first request is held: that run is still in flight when it is superseded.
                let call = episodeReads.withLock { count in
                    count += 1
                    return count
                }
                return call == 1 ? StubResponse.emptyArray.held(by: slow) : .emptyArray
            case "external_links": return Self.animeCatalog
            default: return .emptyArray
            }
        }
        let availability = harness.availability
        let superseded = Task { @MainActor in
            await availability.resolveWatchLinks(animeId: Self.animeId, originalLanguage: nil, progress: 1, locale: "en_US")
        }
        _ = await harness.server.waitForRequest { $0.resource == "episodes" }
        // `.task(id: progress)` moved on: SwiftUI cancels the old run and starts a new one.
        superseded.cancel()
        _ = await harness.server.waitForStop { $0.resource == "episodes" }
        let current = try #require(await availability.resolveWatchLinks(
            animeId: Self.animeId, originalLanguage: nil, progress: 2, locale: "en_US"))
        #expect(current.all.map(\.title) == ["Crunchyroll", "Netflix"])

        slow.open()
        #expect(await superseded.value == nil)
        await harness.tearDown()
    }

    // MARK: Outbound URL allowlist

    /// Hostile, odd and legitimate inputs for the outbound-URL guarantee.
    nonisolated static let outboundCorpus: [String?] = [
        nil, "", "   ",
        // Other schemes, mixed case, scheme-relative and port tricks.
        "javascript:alert(1)", "JavaScript:alert(document.cookie)", "JAVASCRIPT:alert(1)", "javascript:1",
        " javascript:alert(1)", "javascript://%0aalert(1)", "data:text/html,<script>alert(1)</script>", "data:,x",
        "file:///etc/passwd", "FILE:///etc/passwd", "file:/etc/passwd", "kuro://anime/1", "Kuro://anime/1", "kuro:1",
        "itms-services://?action=download", "intent://x#Intent;end", "tel:123", "mailto:a@b.c", "ftp://x.com/a", "ws://x.com",
        // Empty host and malformed hosts.
        "http://", "https://", "HTTP://", "https:// ", "//evil.com/x", "/relative/path", "?q=1", "#frag",
        "https://\\evil.com", "https://exa[mple.com", "https://ex%ample.com", "https://example.com\u{0000}.evil.com",
        "https://x.com\nhttps://y.com",
        // Credentials in the URL.
        "https://user:pass@evil.com/x", "https://example.com@evil.com", "javascript:alert(1)@evil.com",
        // Legitimate: mixed-case schemes, scheme-less hosts, spaces, non-ASCII.
        "http://example.com/a", "HTTPS://Example.com/A", "hTtP://x.com", " https://www.crunchyroll.com/series/x y ",
        "www.netflix.com/title/1", "netflix.com", "https://例え.jp/パス", "例え.jp/パス",
        "https://www.crunchyroll.com/シリーズ/進撃", "https://ＥＸＡＭＰＬＥ.com",
    ]

    @Test("Outbound-URL guarantee: any non-nil result is http/https with a non-empty host (hostile, malformed and credential inputs)")
    func outboundURLGuarantee() {
        for input in Self.outboundCorpus {
            guard let url = ProviderAvailabilityStore.validatedOutboundURL(input) else { continue }
            let scheme = url.scheme?.lowercased()
            #expect(scheme == "http" || scheme == "https", "\(String(reflecting: input)) -> \(url.absoluteString)")
            #expect(!(url.host() ?? "").isEmpty, "\(String(reflecting: input)) -> \(url.absoluteString)")
        }
    }

    @Test("One outbound-URL validator: other schemes, empty hosts and malformed hosts are rejected; legitimate links are kept")
    func outboundURLSchemeAllowlist() {
        let validate = ProviderAvailabilityStore.validatedOutboundURL
        let rejected: [String?] = [
            nil, "   ", "javascript:alert(1)", "JavaScript:alert(document.cookie)", "file:///etc/passwd", "FILE:///etc/passwd",
            "data:text/html,<script>alert(1)</script>", "kuro://anime/1", "Kuro://anime/1", "intent://x#Intent;end",
            "mailto:a@b.c", "tel:123", "javascript:443", "javascript:alert(1)@evil.com",
            "netflix.com:443/title/1",
            // Empty host.
            "http://", "https://", "HTTP://", "//evil.com/x", "/relative/path", "?q=1", "#frag",
            // Malformed hosts (rejected, not percent-encoded into a dead link).
            "https://\\evil.com", "https://exa[mple.com", "https://ex%ample.com", "https://example.com\u{0000}.evil.com",
            "https://x.com\nhttps://y.com",
        ]
        for input in rejected {
            #expect(validate(input) == nil, "\(String(reflecting: input))")
        }
        let accepted: [(input: String, url: String)] = [
            ("  https://www.crunchyroll.com/series/x y ", "https://www.crunchyroll.com/series/x%20y"),
            ("www.netflix.com/title/1", "https://www.netflix.com/title/1"),
            ("netflix.com", "https://netflix.com"),
            ("http://example.com/a", "http://example.com/a"),
            ("https://example.com:443/a", "https://example.com:443/a"),
            ("HTTPS://Example.com/A", "HTTPS://Example.com/A"),
            ("https://例え.jp/パス", "https://xn--r8jz45g.jp/%E3%83%91%E3%82%B9"),
            ("例え.jp/パス", "https://xn--r8jz45g.jp/%E3%83%91%E3%82%B9"),
            ("https://www.crunchyroll.com/シリーズ/進撃", "https://www.crunchyroll.com/%E3%82%B7%E3%83%AA%E3%83%BC%E3%82%BA/%E9%80%B2%E6%92%83"),
            ("https://ＥＸＡＭＰＬＥ.com", "https://example.com"),
        ]
        for (input, url) in accepted {
            #expect(validate(input)?.absoluteString == url, "\(input)")
        }
        // Credentials stay in the URL; the host that opens is the real one.
        #expect(validate("https://user:pass@evil.com/x")?.host() == "evil.com")
        #expect(ProviderAvailabilityStore.isValidHttpURL(" HTTPS://example.com "))
        #expect(!ProviderAvailabilityStore.isValidHttpURL("javascript:alert(1)"))
    }

    @Test("The snapshot never carries a non-http link: a verified provider with a javascript: URL is dropped and the catalog fallback is shown")
    func snapshotDropsNonHTTPLinks() async throws {
        let harness = try DetailLinksHarness(streamingAvailability: true) { request in
            switch request.resource {
            case "external_links":
                return Self.externalLinks(
                    [(id: 1, site: "Crunchyroll", url: Self.crunchyrollURL), (id: 5, site: "Netflix", url: "file:///etc/passwd")],
                    mediaType: "ANIME", mediaId: Self.animeId)
            case "rpc/get_media_availability_status": return Self.freshStatus
            case "rpc/batch_provider_availability_for_media_v2":
                return Self.providerBatch(mediaType: "ANIME", mediaId: Self.animeId, url: "javascript:alert(1)", isStale: false)
            default: return .emptyArray
            }
        }
        let snapshot = try #require(await harness.availability.resolveWatchLinks(
            animeId: Self.animeId, originalLanguage: nil, progress: nil, locale: "en_US"))
        #expect(snapshot.all.map(\.url) == [Self.crunchyrollURL])
        #expect(snapshot.all.allSatisfy { !$0.isVerified })
        #expect(snapshot.note == "Catalog links only. Verified availability is still being refreshed.")
        await harness.tearDown()
    }
}
