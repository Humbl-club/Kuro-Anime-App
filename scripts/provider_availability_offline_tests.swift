import Foundation

struct ProviderAvailabilityTestError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

final class FakeProviderTransport: ProviderTitleTransport {
    var hitsByQuery: [String: [WatchmodeSearchHit]] = [:]
    var sourcesByTitleId: [String: [[String: Any]]] = [:]
    var failingTitleIds: Set<String> = []

    func searchTitles(_ query: String) async throws -> [WatchmodeSearchHit] {
        hitsByQuery[query] ?? []
    }

    func fetchTitleSources(titleId: String) async throws -> [[String: Any]] {
        if failingTitleIds.contains(titleId) {
            throw ProviderWorkerError.invalidResponse("watchmode_sources_failed")
        }
        return sourcesByTitleId[titleId] ?? []
    }
}

final class FakeProviderStore: ProviderAvailabilityRepository {
    let candidates: [Candidate]
    let seeds: [Int: MediaSeed]
    let services: [StreamingServiceRecord]
    var availability: [AvailabilityUpsert] = []
    var refresh: [RefreshStateUpsert] = []
    var sourceMaps: [SourceMapUpsert] = []

    init(candidates: [Candidate], seeds: [Int: MediaSeed], services: [StreamingServiceRecord]) {
        self.candidates = candidates
        self.seeds = seeds
        self.services = services
    }

    func streamingServices() async throws -> [StreamingServiceRecord] { services }

    func refreshCandidates(limit: Int, forceMediaType: String?, forceMediaId: Int?, staleDays: Int) async throws -> [Candidate] {
        Array(candidates.prefix(limit))
    }

    func mediaSeed(mediaType: String, mediaId: Int) async throws -> MediaSeed {
        guard let seed = seeds[mediaId] else {
            throw ProviderAvailabilityTestError(message: "missing seed \(mediaId)")
        }
        return seed
    }

    func activeSourceId(mediaType: String, mediaId: Int) async throws -> String? { nil }

    func saveSourceMap(_ row: SourceMapUpsert) async throws {
        sourceMaps.append(row)
    }

    func saveAvailability(_ rows: [AvailabilityUpsert]) async throws {
        availability.append(contentsOf: rows)
    }

    func refreshState(mediaType: String, mediaId: Int) async throws -> RefreshStateRow? { nil }

    func saveRefreshState(_ row: RefreshStateUpsert) async throws {
        refresh.append(row)
    }

    func softStaleCount(mediaType: String, mediaId: Int, graceDays: Int) async throws -> Int { 0 }

    func queueSummary() async throws -> QueueSummary {
        QueueSummary(urgent_pending_count: 0, oldest_pending_request_age_seconds: 0, request_reason_mix: [:])
    }
}

@main
struct ProviderAvailabilityOfflineTests {
    static func main() async {
        do {
            let checks = try await runOffline()
            fputs("provider_availability_offline_tests passed \(checks) checks\n", stderr)
        } catch {
            fputs("provider_availability_offline_tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func runOffline() async throws -> Int {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            if !condition { throw ProviderAvailabilityTestError(message: message) }
            checks += 1
        }

        let services = [
            StreamingServiceRecord(
                slug: "netflix",
                display_name: "Netflix",
                site_patterns: ["netflix"],
                priority: 1,
                is_active: true
            )
        ]
        let successSeed = MediaSeed(
            id: 7,
            title_english: "Cowboy Bebop",
            title_romaji: nil,
            title_native: nil,
            season_year: 1998,
            start_date_year: nil
        )
        let failureSeed = MediaSeed(
            id: 8,
            title_english: "Neon Diner",
            title_romaji: nil,
            title_native: nil,
            season_year: 2004,
            start_date_year: nil
        )
        let store = FakeProviderStore(
            candidates: [
                Candidate(media_type: "ANIME", media_id: 7),
                Candidate(media_type: "ANIME", media_id: 8)
            ],
            seeds: [7: successSeed, 8: failureSeed],
            services: services
        )
        let transport = FakeProviderTransport()
        transport.hitsByQuery["Cowboy Bebop"] = [WatchmodeSearchHit(id: "111", title: "Cowboy Bebop", year: 1998)]
        transport.hitsByQuery["Neon Diner"] = [WatchmodeSearchHit(id: "999", title: "Neon Diner", year: 2004)]
        transport.sourcesByTitleId["111"] = [[
            "name": "Netflix",
            "region": "US",
            "type": "sub",
            "web_url": "https://www.netflix.com/title/800000",
            "audio_languages": ["ja"],
            "subtitle_languages": ["en"]
        ]]
        transport.failingTitleIds = ["999"]

        let reportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-availability-offline-\(UUID().uuidString)", isDirectory: true)
            .path
        try await runProviderAvailability(
            config: ProviderAvailabilityRunConfig(
                limit: 10,
                staleDays: 30,
                graceDays: 90,
                forceMediaType: nil,
                forceMediaId: nil,
                timeBudgetMs: 60_000
            ),
            transport: transport,
            store: store,
            reportDir: reportDir
        )

        try expect(store.availability.count == 1, "availability rows \(store.availability.count)")
        let row = store.availability[0]
        try expect(row.media_id == 7, "success media id")
        try expect(row.provider_slug == "netflix", "slug \(row.provider_slug)")
        try expect(row.country_code == "US", "country \(row.country_code)")
        try expect(row.availability_type == "subscription", "type \(row.availability_type)")
        try expect(row.audio_langs == ["ja"], "audio \(row.audio_langs)")
        try expect(row.subtitle_langs == ["en"], "subs \(row.subtitle_langs)")
        try expect(row.web_url == "https://www.netflix.com/title/800000", "url")
        try expect(store.availability.allSatisfy { $0.media_id != 8 }, "invented availability for provider failure")
        try expect(store.refresh.contains { $0.media_id == 7 && $0.status == "ok" && $0.last_error == nil }, "success refresh")
        try expect(store.refresh.contains { $0.media_id == 8 && $0.status == "error" }, "error checkpoint")
        let errorRefresh = store.refresh.first { $0.media_id == 8 }
        try expect(errorRefresh?.last_error?.contains("watchmode_sources_failed") == true, "error text")
        try expect(store.sourceMaps.contains { $0.media_id == 7 && $0.status == "active" && $0.source_media_id == "111" }, "mapped success")

        let status = readStatus(from: "\(reportDir)/latest-status.json")
        try expect(status?.last_run.candidates == 2, "candidate count")
        try expect(status?.last_run.processed == 1, "processed \(status?.last_run.processed ?? -1)")
        try expect(status?.last_run.offers_upserted == 1, "offers \(status?.last_run.offers_upserted ?? -1)")
        try expect(status?.last_run.api_errors == 1, "api errors \(status?.last_run.api_errors ?? -1)")
        try expect(status?.last_run.countries_written == 1, "countries")
        let unresolved = try String(contentsOfFile: "\(reportDir)/unresolved-latest.md", encoding: .utf8)
        try expect(unresolved.contains("No unresolved mappings"), "unresolved report invented a mapping")

        return checks
    }
}
