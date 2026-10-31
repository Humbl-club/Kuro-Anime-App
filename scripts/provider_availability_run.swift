import Foundation

struct Candidate: Decodable {
    let media_type: String
    let media_id: Int
}

struct ProviderSourceMapRow: Decodable {
    let source_media_id: String
    let status: String
    let confidence: Double?
}

struct RefreshStateRow: Decodable {
    let retry_count: Int
    let request_reason: String?
    let last_requested_at: Date?
}

struct MediaSeed: Decodable {
    let id: Int
    let title_english: String?
    let title_romaji: String?
    let title_native: String?
    let season_year: Int?
    let start_date_year: Int?
}

struct RunMetrics: Codable {
    var started_at: String
    var finished_at: String
    var candidates: Int
    var processed: Int
    var mapped_new: Int
    var mapping_unresolved: Int
    var offers_upserted: Int
    var countries_written: Int
    var api_errors: Int
    var stale_soft_expired: Int
    var duration_ms: Int
}

struct CumulativeTotals: Codable {
    var runs: Int
    var processed: Int
    var mapped_new: Int
    var mapping_unresolved: Int
    var offers_upserted: Int
    var api_errors: Int
}

struct QueueSummary: Codable {
    var urgent_pending_count: Int
    var oldest_pending_request_age_seconds: Int
    var request_reason_mix: [String: Int]
}

struct WorkerStatus: Codable {
    var updated_at: String
    var last_run: RunMetrics
    var totals: CumulativeTotals
    var queue_summary: QueueSummary?
}

struct QueueSummaryPayload: Decodable {
    let urgent_pending_count: Int?
    let oldest_pending_request_age_seconds: Int?
    let request_reason_mix: [String: Int]?
}

struct UnresolvedEntry {
    let mediaType: String
    let mediaId: Int
    let title: String
    let reason: String
}

struct SourceMapUpsert: Encodable {
    let media_type: String
    let media_id: Int
    let source_name: String
    let source_media_id: String
    let match_method: String
    let confidence: Double
    let status: String
    let last_verified_at: String?
    let updated_at: String
}

struct RefreshStateUpsert: Encodable {
    let media_type: String
    let media_id: Int
    let source_name: String
    let status: String
    let last_refreshed_at: String?
    let next_refresh_at: String
    let retry_count: Int
    let last_error: String?
    let updated_at: String
}

struct ProviderAvailabilityRunConfig {
    let limit: Int
    let staleDays: Int
    let graceDays: Int
    let forceMediaType: String?
    let forceMediaId: Int?
    let timeBudgetMs: Int
}

protocol ProviderTitleTransport {
    func searchTitles(_ query: String) async throws -> [WatchmodeSearchHit]
    func fetchTitleSources(titleId: String) async throws -> [[String: Any]]
}

protocol ProviderAvailabilityRepository {
    func streamingServices() async throws -> [StreamingServiceRecord]
    func refreshCandidates(limit: Int, forceMediaType: String?, forceMediaId: Int?, staleDays: Int) async throws -> [Candidate]
    func mediaSeed(mediaType: String, mediaId: Int) async throws -> MediaSeed
    func activeSourceId(mediaType: String, mediaId: Int) async throws -> String?
    func saveSourceMap(_ row: SourceMapUpsert) async throws
    func saveAvailability(_ rows: [AvailabilityUpsert]) async throws
    func refreshState(mediaType: String, mediaId: Int) async throws -> RefreshStateRow?
    func saveRefreshState(_ row: RefreshStateUpsert) async throws
    func softStaleCount(mediaType: String, mediaId: Int, graceDays: Int) async throws -> Int
    func queueSummary() async throws -> QueueSummary
}

extension JSONDecoder {
    static var providerWorker: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var providerWorker: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}

func writeText(_ text: String, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try text.data(using: .utf8)?.write(to: url)
}

func readStatus(from path: String) -> WorkerStatus? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return try? JSONDecoder.providerWorker.decode(WorkerStatus.self, from: data)
}

func runProviderAvailability<Transport: ProviderTitleTransport, Store: ProviderAvailabilityRepository>(
    config: ProviderAvailabilityRunConfig,
    transport: Transport,
    store: Store,
    reportDir: String
) async throws {
    let services = try await store.streamingServices()

    var metrics = RunMetrics(
        started_at: nowISO8601(),
        finished_at: nowISO8601(),
        candidates: 0,
        processed: 0,
        mapped_new: 0,
        mapping_unresolved: 0,
        offers_upserted: 0,
        countries_written: 0,
        api_errors: 0,
        stale_soft_expired: 0,
        duration_ms: 0
    )

    let start = Date()
    let candidates = try await store.refreshCandidates(
        limit: config.limit,
        forceMediaType: config.forceMediaType,
        forceMediaId: config.forceMediaId,
        staleDays: config.staleDays
    )
    metrics.candidates = candidates.count

    var unresolved: [UnresolvedEntry] = []

    for candidate in candidates {
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        if elapsed >= config.timeBudgetMs { break }

        let mediaType = candidate.media_type.uppercased()
        let mediaId = candidate.media_id

        do {
            let seed = try await store.mediaSeed(mediaType: mediaType, mediaId: mediaId)
            guard let sourceId = try await resolveProviderSourceId(
                transport: transport,
                store: store,
                seed: seed,
                mediaType: mediaType,
                mediaId: mediaId,
                unresolved: &unresolved,
                mappedCounter: &metrics.mapped_new,
                unresolvedCounter: &metrics.mapping_unresolved
            ) else {
                let refreshState = try await store.refreshState(mediaType: mediaType, mediaId: mediaId)
                let retry = refreshState?.retry_count ?? 0
                let next = Date().addingTimeInterval(
                    unresolvedRetryInterval(retryCount: retry, requestReason: refreshState?.request_reason)
                )
                let refresh = RefreshStateUpsert(
                    media_type: mediaType,
                    media_id: mediaId,
                    source_name: "watchmode",
                    status: "unresolved",
                    last_refreshed_at: nil,
                    next_refresh_at: isoDate(next),
                    retry_count: retry + 1,
                    last_error: "mapping_unresolved",
                    updated_at: nowISO8601()
                )
                try await store.saveRefreshState(refresh)
                metrics.processed += 1
                continue
            }

            let offers = try await transport.fetchTitleSources(titleId: sourceId)
            let transformed = transformOffers(
                offers: offers,
                mediaType: mediaType,
                mediaId: mediaId,
                services: services
            )

            if !transformed.rows.isEmpty {
                try await store.saveAvailability(transformed.rows)
                metrics.offers_upserted += transformed.rows.count
                metrics.countries_written += transformed.countryCount
            }

            let next = Date().addingTimeInterval(Double(config.staleDays) * 86400)
            let refresh = RefreshStateUpsert(
                media_type: mediaType,
                media_id: mediaId,
                source_name: "watchmode",
                status: "ok",
                last_refreshed_at: nowISO8601(),
                next_refresh_at: isoDate(next),
                retry_count: 0,
                last_error: nil,
                updated_at: nowISO8601()
            )
            try await store.saveRefreshState(refresh)

            metrics.stale_soft_expired += try await store.softStaleCount(
                mediaType: mediaType,
                mediaId: mediaId,
                graceDays: config.graceDays
            )
            metrics.processed += 1
        } catch {
            metrics.api_errors += 1
            let retry = (try? await store.refreshState(mediaType: mediaType, mediaId: mediaId)?.retry_count) ?? 0
            let backoffHours = min(24, Int(pow(2.0, Double(min(retry, 5)))))
            let refresh = RefreshStateUpsert(
                media_type: mediaType,
                media_id: mediaId,
                source_name: "watchmode",
                status: "error",
                last_refreshed_at: nil,
                next_refresh_at: isoDate(Date().addingTimeInterval(Double(backoffHours) * 3600)),
                retry_count: retry + 1,
                last_error: String(describing: error),
                updated_at: nowISO8601()
            )
            try? await store.saveRefreshState(refresh)
        }
    }

    metrics.finished_at = nowISO8601()
    metrics.duration_ms = Int(Date().timeIntervalSince(start) * 1000)

    let stamp = metrics.finished_at.replacingOccurrences(of: ":", with: "-")
    let runLogPath = "\(reportDir)/run-\(stamp).log"

    let runLine = [
        "started_at=\(metrics.started_at)",
        "finished_at=\(metrics.finished_at)",
        "candidates=\(metrics.candidates)",
        "processed=\(metrics.processed)",
        "mapped_new=\(metrics.mapped_new)",
        "mapping_unresolved=\(metrics.mapping_unresolved)",
        "offers_upserted=\(metrics.offers_upserted)",
        "countries_written=\(metrics.countries_written)",
        "api_errors=\(metrics.api_errors)",
        "stale_soft_expired=\(metrics.stale_soft_expired)",
        "duration_ms=\(metrics.duration_ms)"
    ].joined(separator: " ")
    try writeText(runLine + "\n", to: runLogPath)

    let statusPath = "\(reportDir)/latest-status.json"
    var status = readStatus(from: statusPath) ?? WorkerStatus(
        updated_at: nowISO8601(),
        last_run: metrics,
        totals: CumulativeTotals(
            runs: 0,
            processed: 0,
            mapped_new: 0,
            mapping_unresolved: 0,
            offers_upserted: 0,
            api_errors: 0
        ),
        queue_summary: nil
    )
    status.updated_at = nowISO8601()
    status.last_run = metrics
    status.totals.runs += 1
    status.totals.processed += metrics.processed
    status.totals.mapped_new += metrics.mapped_new
    status.totals.mapping_unresolved += metrics.mapping_unresolved
    status.totals.offers_upserted += metrics.offers_upserted
    status.totals.api_errors += metrics.api_errors
    status.queue_summary = (try? await store.queueSummary()) ?? status.queue_summary

    let statusData = try JSONEncoder.providerWorker.encode(status)
    try writeText(String(decoding: statusData, as: UTF8.self), to: statusPath)

    try writeUnresolvedReport(unresolved, reportDir: reportDir)
}

func resolveProviderSourceId<Transport: ProviderTitleTransport, Store: ProviderAvailabilityRepository>(
    transport: Transport,
    store: Store,
    seed: MediaSeed,
    mediaType: String,
    mediaId: Int,
    unresolved: inout [UnresolvedEntry],
    mappedCounter: inout Int,
    unresolvedCounter: inout Int
) async throws -> String? {
    if let existingId = try await store.activeSourceId(mediaType: mediaType, mediaId: mediaId), !existingId.isEmpty {
        return existingId
    }

    var localTitles: [String] = [seed.title_english, seed.title_romaji, seed.title_native]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    localTitles = Array(NSOrderedSet(array: localTitles)) as? [String] ?? localTitles

    guard !localTitles.isEmpty else {
        unresolved.append(UnresolvedEntry(mediaType: mediaType, mediaId: mediaId, title: "Unknown", reason: "missing_title"))
        unresolvedCounter += 1
        try await store.saveSourceMap(
            SourceMapUpsert(
                media_type: mediaType,
                media_id: mediaId,
                source_name: "watchmode",
                source_media_id: "unresolved-\(mediaType)-\(mediaId)",
                match_method: "title_year",
                confidence: 0,
                status: "unresolved",
                last_verified_at: nil,
                updated_at: nowISO8601()
            )
        )
        return nil
    }

    var hitsByID: [String: WatchmodeSearchHit] = [:]
    for title in localTitles.prefix(3) {
        let hits = try await transport.searchTitles(title)
        for hit in hits.prefix(20) {
            hitsByID[hit.id] = hit
        }
    }

    let hits = Array(hitsByID.values)
    guard !hits.isEmpty else {
        unresolved.append(UnresolvedEntry(mediaType: mediaType, mediaId: mediaId, title: localTitles[0], reason: "no_candidates"))
        unresolvedCounter += 1
        try await store.saveSourceMap(
            SourceMapUpsert(
                media_type: mediaType,
                media_id: mediaId,
                source_name: "watchmode",
                source_media_id: "unresolved-\(mediaType)-\(mediaId)",
                match_method: "title_year",
                confidence: 0,
                status: "unresolved",
                last_verified_at: nil,
                updated_at: nowISO8601()
            )
        )
        return nil
    }

    let localYear = seed.season_year ?? seed.start_date_year
    let scored = scoreHits(hits: hits, localTitles: localTitles, localYear: localYear)
    guard let top = scored.first else {
        unresolved.append(UnresolvedEntry(mediaType: mediaType, mediaId: mediaId, title: localTitles[0], reason: "score_failed"))
        unresolvedCounter += 1
        return nil
    }
    let margin = top.score - (scored.dropFirst().first?.score ?? 0)

    guard top.score >= 0.95, margin >= 0.10 else {
        unresolved.append(UnresolvedEntry(
            mediaType: mediaType,
            mediaId: mediaId,
            title: localTitles[0],
            reason: "low_confidence score=\(String(format: "%.3f", top.score)) margin=\(String(format: "%.3f", margin))"
        ))
        unresolvedCounter += 1
        try await store.saveSourceMap(
            SourceMapUpsert(
                media_type: mediaType,
                media_id: mediaId,
                source_name: "watchmode",
                source_media_id: "unresolved-\(mediaType)-\(mediaId)",
                match_method: "title_year",
                confidence: top.score,
                status: "unresolved",
                last_verified_at: nil,
                updated_at: nowISO8601()
            )
        )
        return nil
    }

    let row = SourceMapUpsert(
        media_type: mediaType,
        media_id: mediaId,
        source_name: "watchmode",
        source_media_id: top.hit.id,
        match_method: "title_year",
        confidence: top.score,
        status: "active",
        last_verified_at: nowISO8601(),
        updated_at: nowISO8601()
    )
    try await store.saveSourceMap(row)
    mappedCounter += 1
    return top.hit.id
}

func writeUnresolvedReport(_ unresolved: [UnresolvedEntry], reportDir: String) throws {
    let latestPath = "\(reportDir)/unresolved-latest.md"
    guard !unresolved.isEmpty else {
        let empty = "# Provider Availability Unresolved\n\nNo unresolved mappings in the latest run.\n"
        try writeText(empty, to: latestPath)
        return
    }

    var lines: [String] = []
    lines.append("# Provider Availability Unresolved")
    lines.append("")
    lines.append("Generated at: \(nowISO8601())")
    lines.append("")
    lines.append("| Media Type | Media ID | Title | Reason |")
    lines.append("| --- | ---: | --- | --- |")
    for item in unresolved {
        lines.append("| \(item.mediaType) | \(item.mediaId) | \(item.title.replacingOccurrences(of: "|", with: "/")) | \(item.reason.replacingOccurrences(of: "|", with: "/")) |")
    }
    lines.append("")
    try writeText(lines.joined(separator: "\n") + "\n", to: latestPath)
}
