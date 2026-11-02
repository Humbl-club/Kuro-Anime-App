import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class RPCClient {
    private let baseURL: URL
    private let serviceRoleKey: String

    init(baseURL: URL, serviceRoleKey: String) {
        self.baseURL = baseURL
        self.serviceRoleKey = serviceRoleKey
    }

    func rpc<T: Decodable>(_ name: String, payload: [String: Any], as _: T.Type) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(serviceRoleKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(serviceRoleKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderWorkerError.invalidResponse("RPC \(name) returned non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw ProviderWorkerError.invalidResponse("RPC \(name) failed (\(http.statusCode)): \(body)")
        }

        return try JSONDecoder.providerWorker.decode(T.self, from: data)
    }

    func select<T: Decodable>(_ table: String, query: [URLQueryItem], as _: T.Type) async throws -> [T] {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else {
            throw ProviderWorkerError.invalidResponse("Invalid select URL for table \(table)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(serviceRoleKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(serviceRoleKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderWorkerError.invalidResponse("Select \(table) returned non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw ProviderWorkerError.invalidResponse("Select \(table) failed (\(http.statusCode)): \(body)")
        }

        return try JSONDecoder.providerWorker.decode([T].self, from: data)
    }

    func upsert<T: Encodable>(_ table: String, rows: [T], onConflict: String) async throws {
        guard !rows.isEmpty else { return }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: onConflict)]
        guard let url = components?.url else {
            throw ProviderWorkerError.invalidResponse("Invalid upsert URL for table \(table)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(serviceRoleKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(serviceRoleKey)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.providerWorker.encode(rows)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderWorkerError.invalidResponse("Upsert \(table) returned non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw ProviderWorkerError.invalidResponse("Upsert \(table) failed (\(http.statusCode)): \(body)")
        }
    }
}

actor WatchmodeRateLimiter {
    private var lastCall: UInt64 = 0
    private let minIntervalNanos: UInt64

    init(maxPerSecond: Double) {
        let interval = max(0.1, 1.0 / maxPerSecond)
        minIntervalNanos = UInt64(interval * 1_000_000_000)
    }

    func waitTurn() async {
        let now = DispatchTime.now().uptimeNanoseconds
        if lastCall == 0 {
            lastCall = now
            return
        }
        let target = lastCall + minIntervalNanos
        if target > now {
            let delta = target - now
            try? await Task.sleep(nanoseconds: delta)
            lastCall = target
        } else {
            lastCall = now
        }
    }
}

final class WatchmodeClient {
    private let apiKey: String
    private let session: URLSession
    private let limiter: WatchmodeRateLimiter
    private let baseURL: String

    init(apiKey: String, maxReqPerSec: Double = 3.0, baseURL: String = "https://api.watchmode.com/v1") {
        self.apiKey = apiKey
        self.session = URLSession(configuration: .default)
        self.limiter = WatchmodeRateLimiter(maxPerSecond: maxReqPerSec)
        self.baseURL = baseURL
    }

    func searchTitles(_ query: String) async throws -> [WatchmodeSearchHit] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var components = URLComponents(string: "\(baseURL)/search/")
        components?.queryItems = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "search_field", value: "name"),
            URLQueryItem(name: "search_value", value: query)
        ]
        guard let url = components?.url else {
            throw ProviderWorkerError.invalidResponse("Invalid Watchmode search URL")
        }

        let data = try await fetch(url: url)
        return parseSearchHits(data: data)
    }

    func fetchTitleSources(titleId: String) async throws -> [[String: Any]] {
        guard !titleId.isEmpty else { return [] }
        var components = URLComponents(string: "\(baseURL)/title/\(titleId)/sources/")
        components?.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]
        guard let url = components?.url else {
            throw ProviderWorkerError.invalidResponse("Invalid Watchmode sources URL")
        }

        let data = try await fetch(url: url)
        let json = try JSONSerialization.jsonObject(with: data)

        if let rows = json as? [[String: Any]] {
            return rows
        }
        if let dict = json as? [String: Any] {
            if let rows = dict["sources"] as? [[String: Any]] {
                return rows
            }
            if let rows = dict["results"] as? [[String: Any]] {
                return rows
            }
        }
        return []
    }

    private func fetch(url: URL) async throws -> Data {
        for attempt in 0..<4 {
            await limiter.waitTurn()
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderWorkerError.invalidResponse("Watchmode returned non-HTTP response")
            }
            if (200..<300).contains(http.statusCode) {
                return data
            }
            if http.statusCode == 429 && attempt < 3 {
                let base = pow(2.0, Double(attempt))
                let jitter = Double.random(in: 0.0...0.4)
                let sleepSeconds = base + jitter
                try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                continue
            }
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw ProviderWorkerError.invalidResponse("Watchmode request failed (\(http.statusCode)): \(body)")
        }
        throw ProviderWorkerError.invalidResponse("Watchmode exhausted retries")
    }

    private func parseSearchHits(data: Data) -> [WatchmodeSearchHit] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var rows: [[String: Any]] = []

        if let array = obj as? [[String: Any]] {
            rows = array
        } else if let dict = obj as? [String: Any] {
            if let titleResults = dict["title_results"] as? [[String: Any]] {
                rows = titleResults
            } else if let results = dict["results"] as? [[String: Any]] {
                rows = results
            }
        }

        var output: [WatchmodeSearchHit] = []
        for row in rows {
            let id: String
            if let intID = row["id"] as? Int {
                id = String(intID)
            } else if let stringID = row["id"] as? String {
                id = stringID
            } else if let titleID = row["title_id"] as? Int {
                id = String(titleID)
            } else if let titleID = row["title_id"] as? String {
                id = titleID
            } else {
                continue
            }

            let title = (row["name"] as? String)
                ?? (row["title"] as? String)
                ?? (row["original_title"] as? String)
                ?? ""
            guard !title.isEmpty else { continue }

            let year: Int?
            if let y = row["year"] as? Int {
                year = y
            } else if let y = row["release_year"] as? Int {
                year = y
            } else if let y = row["year"] as? String {
                year = Int(y)
            } else {
                year = nil
            }

            output.append(WatchmodeSearchHit(id: id, title: title, year: year))
        }
        return output
    }
}

extension WatchmodeClient: ProviderTitleTransport {}

struct LiveProviderAvailabilityRepository: ProviderAvailabilityRepository {
    let rpc: RPCClient

    func streamingServices() async throws -> [StreamingServiceRecord] {
        try await rpc.select(
            "streaming_services",
            query: [
                URLQueryItem(name: "select", value: "slug,display_name,site_patterns,priority,is_active"),
                URLQueryItem(name: "is_active", value: "eq.true"),
                URLQueryItem(name: "order", value: "priority.asc")
            ],
            as: StreamingServiceRecord.self
        )
    }

    func refreshCandidates(limit: Int, forceMediaType: String?, forceMediaId: Int?, staleDays: Int) async throws -> [Candidate] {
        try await rpc.rpc(
            "get_provider_availability_refresh_candidates",
            payload: [
                "p_limit": limit,
                "p_force_media_type": forceMediaType as Any,
                "p_force_media_id": forceMediaId as Any,
                "p_stale_days": staleDays
            ],
            as: [Candidate].self
        )
    }

    func mediaSeed(mediaType: String, mediaId: Int) async throws -> MediaSeed {
        let table = mediaType == "MANGA" ? "manga" : "anime"
        let rows: [MediaSeed] = try await rpc.select(
            table,
            query: [
                URLQueryItem(name: "select", value: "id,title_english,title_romaji,title_native,season_year,start_date_year"),
                URLQueryItem(name: "id", value: "eq.\(mediaId)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            as: MediaSeed.self
        )
        guard let first = rows.first else {
            throw ProviderWorkerError.invalidResponse("Missing \(table) row id=\(mediaId)")
        }
        return first
    }

    func activeSourceId(mediaType: String, mediaId: Int) async throws -> String? {
        let existing: [ProviderSourceMapRow] = try await rpc.select(
            "provider_source_map",
            query: [
                URLQueryItem(name: "select", value: "source_media_id,status,confidence"),
                URLQueryItem(name: "media_type", value: "eq.\(mediaType)"),
                URLQueryItem(name: "media_id", value: "eq.\(mediaId)"),
                URLQueryItem(name: "source_name", value: "eq.watchmode"),
                URLQueryItem(name: "status", value: "eq.active"),
                URLQueryItem(name: "limit", value: "1")
            ],
            as: ProviderSourceMapRow.self
        )
        return existing.first?.source_media_id
    }

    func saveSourceMap(_ row: SourceMapUpsert) async throws {
        try await rpc.upsert(
            "provider_source_map",
            rows: [row],
            onConflict: "media_type,media_id,source_name"
        )
    }

    func saveAvailability(_ rows: [AvailabilityUpsert]) async throws {
        try await rpc.upsert(
            "provider_availability",
            rows: rows,
            onConflict: "media_type,media_id,provider_slug,country_code,availability_type"
        )
    }

    func refreshState(mediaType: String, mediaId: Int) async throws -> RefreshStateRow? {
        let rows: [RefreshStateRow] = try await rpc.select(
            "provider_availability_refresh_state",
            query: [
                URLQueryItem(name: "select", value: "retry_count,request_reason,last_requested_at"),
                URLQueryItem(name: "media_type", value: "eq.\(mediaType)"),
                URLQueryItem(name: "media_id", value: "eq.\(mediaId)"),
                URLQueryItem(name: "source_name", value: "eq.watchmode"),
                URLQueryItem(name: "limit", value: "1")
            ],
            as: RefreshStateRow.self
        )
        return rows.first
    }

    func saveRefreshState(_ row: RefreshStateUpsert) async throws {
        try await rpc.upsert(
            "provider_availability_refresh_state",
            rows: [row],
            onConflict: "media_type,media_id,source_name"
        )
    }

    func softStaleCount(mediaType: String, mediaId: Int, graceDays: Int) async throws -> Int {
        struct CountRow: Decodable { let id: Int }
        let cutoff = isoDate(Date().addingTimeInterval(Double(-graceDays) * 86400))
        let staleRows: [CountRow] = try await rpc.select(
            "provider_availability",
            query: [
                URLQueryItem(name: "select", value: "id"),
                URLQueryItem(name: "media_type", value: "eq.\(mediaType)"),
                URLQueryItem(name: "media_id", value: "eq.\(mediaId)"),
                URLQueryItem(name: "last_seen_at", value: "lt.\(cutoff)"),
                URLQueryItem(name: "limit", value: "1000")
            ],
            as: CountRow.self
        )
        return staleRows.count
    }

    func queueSummary() async throws -> QueueSummary {
        let payload: QueueSummaryPayload = try await rpc.rpc(
            "get_provider_availability_refresh_queue_summary",
            payload: [:],
            as: QueueSummaryPayload.self
        )
        return QueueSummary(
            urgent_pending_count: payload.urgent_pending_count ?? 0,
            oldest_pending_request_age_seconds: payload.oldest_pending_request_age_seconds ?? 0,
            request_reason_mix: payload.request_reason_mix ?? [:]
        )
    }
}

@main
struct ProviderAvailabilityWorker {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("provider_availability_worker error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let supabaseURLRaw = env["SUPABASE_URL"], !supabaseURLRaw.isEmpty else {
            throw ProviderWorkerError.missingEnv("SUPABASE_URL")
        }
        guard let serviceRole = env["SUPABASE_SERVICE_ROLE_KEY"], !serviceRole.isEmpty else {
            throw ProviderWorkerError.missingEnv("SUPABASE_SERVICE_ROLE_KEY")
        }
        guard let watchmodeApiKey = env["WATCHMODE_API_KEY"], !watchmodeApiKey.isEmpty else {
            throw ProviderWorkerError.missingEnv("WATCHMODE_API_KEY")
        }
        guard let supabaseURL = URL(string: supabaseURLRaw) else {
            throw ProviderWorkerError.invalidResponse("Invalid SUPABASE_URL: \(supabaseURLRaw)")
        }

        let reportDir = env["PROVIDER_AVAILABILITY_REPORTS_DIR"] ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("reports/provider-availability").path
        let limit = max(1, Int(env["PROVIDER_AVAILABILITY_BATCH_SIZE"] ?? "100") ?? 100)
        let staleDays = max(1, Int(env["PROVIDER_AVAILABILITY_STALE_DAYS"] ?? "30") ?? 30)
        let graceDays = max(staleDays, Int(env["PROVIDER_AVAILABILITY_GRACE_DAYS"] ?? "90") ?? 90)
        let forceMediaType = env["PROVIDER_AVAILABILITY_FORCE_MEDIA_TYPE"]
        let forceMediaId = Int(env["PROVIDER_AVAILABILITY_FORCE_MEDIA_ID"] ?? "")
        let timeBudgetMs = max(10_000, Int(env["PROVIDER_AVAILABILITY_TIME_BUDGET_MS"] ?? "45000") ?? 45000)

        let rpc = RPCClient(baseURL: supabaseURL, serviceRoleKey: serviceRole)
        let watchmode = WatchmodeClient(apiKey: watchmodeApiKey, maxReqPerSec: 3.0)
        try await runProviderAvailability(
            config: ProviderAvailabilityRunConfig(
                limit: limit,
                staleDays: staleDays,
                graceDays: graceDays,
                forceMediaType: forceMediaType,
                forceMediaId: forceMediaId,
                timeBudgetMs: timeBudgetMs
            ),
            transport: watchmode,
            store: LiveProviderAvailabilityRepository(rpc: rpc),
            reportDir: reportDir
        )
    }
}
