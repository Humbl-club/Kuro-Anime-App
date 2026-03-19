import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ProviderWorkerError: Error, CustomStringConvertible {
    case missingEnv(String)
    case invalidResponse(String)

    var description: String {
        switch self {
        case .missingEnv(let key):
            return "Missing env var: \(key)"
        case .invalidResponse(let msg):
            return msg
        }
    }
}

struct Candidate: Decodable {
    let media_type: String
    let media_id: Int
}

struct StreamingServiceRecord: Decodable {
    let slug: String
    let display_name: String
    let site_patterns: [String]
    let priority: Int
    let is_active: Bool
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

struct WatchmodeSearchHit {
    let id: String
    let title: String
    let year: Int?
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

struct WorkerStatus: Codable {
    var updated_at: String
    var last_run: RunMetrics
    var totals: CumulativeTotals
    var queue_summary: QueueSummary?
}

struct QueueSummary: Codable {
    var urgent_pending_count: Int
    var oldest_pending_request_age_seconds: Int
    var request_reason_mix: [String: Int]
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

struct AvailabilityUpsert: Encodable {
    let media_type: String
    let media_id: Int
    let provider_slug: String
    let country_code: String
    let availability_type: String
    let audio_langs: [String]
    let subtitle_langs: [String]
    let deep_link_url: String?
    let web_url: String?
    let source_name: String
    let source_offer_id: String?
    let last_seen_at: String
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

struct QueueSummaryPayload: Decodable {
    let urgent_pending_count: Int?
    let oldest_pending_request_age_seconds: Int?
    let request_reason_mix: [String: Int]?
}

struct AvailabilityKey: Hashable {
    let mediaType: String
    let mediaId: Int
    let providerSlug: String
    let countryCode: String
    let availabilityType: String
}

struct AvailabilityAggregate {
    var audioLangs: Set<String>
    var subtitleLangs: Set<String>
    var deepLinkURL: String?
    var webURL: String?
    var sourceOfferID: String?
}

struct ScoredHit {
    let hit: WatchmodeSearchHit
    let score: Double
}

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

func nowISO8601() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func normalizeTitle(_ text: String) -> String {
    text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func tokenSet(_ text: String) -> Set<String> {
    Set(normalizeTitle(text).split(separator: " ").map(String.init).filter { !$0.isEmpty })
}

func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
    if lhs.isEmpty && rhs.isEmpty { return 1 }
    let intersection = lhs.intersection(rhs).count
    let union = lhs.union(rhs).count
    guard union > 0 else { return 0 }
    return Double(intersection) / Double(union)
}

func levenshteinDistance(_ a: String, _ b: String) -> Int {
    let lhs = Array(a)
    let rhs = Array(b)
    if lhs.isEmpty { return rhs.count }
    if rhs.isEmpty { return lhs.count }

    var costs = Array(0...rhs.count)
    for i in 1...lhs.count {
        var previous = costs[0]
        costs[0] = i
        for j in 1...rhs.count {
            let tmp = costs[j]
            let substitution = previous + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
            let insertion = costs[j] + 1
            let deletion = costs[j - 1] + 1
            costs[j] = min(substitution, min(insertion, deletion))
            previous = tmp
        }
    }
    return costs[rhs.count]
}

func similarity(_ lhs: String, _ rhs: String) -> Double {
    let left = normalizeTitle(lhs)
    let right = normalizeTitle(rhs)
    guard !left.isEmpty, !right.isEmpty else { return 0 }

    let tokens = jaccard(tokenSet(left), tokenSet(right))
    let lev = levenshteinDistance(left, right)
    let maxLen = max(left.count, right.count)
    let edit = maxLen > 0 ? 1.0 - (Double(lev) / Double(maxLen)) : 0

    return max(0, min(1, 0.55 * edit + 0.45 * tokens))
}

func unresolvedRetryInterval(retryCount: Int, requestReason: String?) -> TimeInterval {
    let normalizedReason = requestReason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let isOnDemand = normalizedReason == "detail_open" || normalizedReason == "user_tap"
    if isOnDemand && retryCount == 0 {
        return 30 * 60
    }
    let backoffHours = min(24, Int(pow(2.0, Double(min(retryCount, 5)))))
    return Double(backoffHours) * 3600
}

func normalizeLanguage(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let cleaned = raw
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }

    if cleaned.count == 2 {
        return String(cleaned.prefix(2))
    }
    if cleaned.hasPrefix("en") || cleaned.contains("english") { return "en" }
    if cleaned.hasPrefix("de") || cleaned.contains("german") || cleaned.contains("deutsch") { return "de" }
    if cleaned.hasPrefix("ja") || cleaned.contains("japanese") { return "ja" }
    if cleaned.hasPrefix("fr") || cleaned.contains("french") { return "fr" }
    if cleaned.hasPrefix("es") || cleaned.contains("spanish") { return "es" }
    if cleaned.hasPrefix("it") || cleaned.contains("italian") { return "it" }
    if cleaned.hasPrefix("pt") || cleaned.contains("portuguese") { return "pt" }

    return String(cleaned.prefix(2))
}

func parseLanguageArray(_ value: Any?) -> [String] {
    if let array = value as? [String] {
        return Array(Set(array.compactMap(normalizeLanguage))).sorted()
    }
    if let string = value as? String {
        let parts = string
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" })
            .map { String($0) }
        return Array(Set(parts.compactMap(normalizeLanguage))).sorted()
    }
    return []
}

func parseCountryCode(_ value: Any?) -> String? {
    guard let raw = value as? String else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard trimmed.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil else {
        return nil
    }
    return trimmed
}

func isoDate(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
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

        let reportDir = env["PROVIDER_AVAILABILITY_REPORTS_DIR"] ?? "/Applications/Kuro/reports/provider-availability"
        let limit = max(1, Int(env["PROVIDER_AVAILABILITY_BATCH_SIZE"] ?? "100") ?? 100)
        let staleDays = max(1, Int(env["PROVIDER_AVAILABILITY_STALE_DAYS"] ?? "30") ?? 30)
        let graceDays = max(staleDays, Int(env["PROVIDER_AVAILABILITY_GRACE_DAYS"] ?? "90") ?? 90)
        let forceMediaType = env["PROVIDER_AVAILABILITY_FORCE_MEDIA_TYPE"]
        let forceMediaId = Int(env["PROVIDER_AVAILABILITY_FORCE_MEDIA_ID"] ?? "")
        let timeBudgetMs = max(10_000, Int(env["PROVIDER_AVAILABILITY_TIME_BUDGET_MS"] ?? "45000") ?? 45000)

        let rpc = RPCClient(baseURL: supabaseURL, serviceRoleKey: serviceRole)
        let watchmode = WatchmodeClient(apiKey: watchmodeApiKey, maxReqPerSec: 3.0)

        let services = try await rpc.select(
            "streaming_services",
            query: [
                URLQueryItem(name: "select", value: "slug,display_name,site_patterns,priority,is_active"),
                URLQueryItem(name: "is_active", value: "eq.true"),
                URLQueryItem(name: "order", value: "priority.asc")
            ],
            as: StreamingServiceRecord.self
        )

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
        let candidates: [Candidate] = try await rpc.rpc(
            "get_provider_availability_refresh_candidates",
            payload: [
                "p_limit": limit,
                "p_force_media_type": forceMediaType as Any,
                "p_force_media_id": forceMediaId as Any,
                "p_stale_days": staleDays
            ],
            as: [Candidate].self
        )
        metrics.candidates = candidates.count

        var unresolved: [UnresolvedEntry] = []

        for candidate in candidates {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            if elapsed >= timeBudgetMs { break }

            let mediaType = candidate.media_type.uppercased()
            let mediaId = candidate.media_id

            do {
                let seed = try await fetchMediaSeed(rpc: rpc, mediaType: mediaType, mediaId: mediaId)
                guard let sourceId = try await resolveSourceId(
                    rpc: rpc,
                    watchmode: watchmode,
                    seed: seed,
                    mediaType: mediaType,
                    mediaId: mediaId,
                    unresolved: &unresolved,
                    mappedCounter: &metrics.mapped_new,
                    unresolvedCounter: &metrics.mapping_unresolved
                ) else {
                    let refreshState = try await fetchRefreshState(rpc: rpc, mediaType: mediaType, mediaId: mediaId)
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
                    try await rpc.upsert(
                        "provider_availability_refresh_state",
                        rows: [refresh],
                        onConflict: "media_type,media_id,source_name"
                    )
                    metrics.processed += 1
                    continue
                }

                let offers = try await watchmode.fetchTitleSources(titleId: sourceId)
                let transformed = transformOffers(
                    offers: offers,
                    mediaType: mediaType,
                    mediaId: mediaId,
                    services: services
                )

                if !transformed.rows.isEmpty {
                    try await rpc.upsert(
                        "provider_availability",
                        rows: transformed.rows,
                        onConflict: "media_type,media_id,provider_slug,country_code,availability_type"
                    )
                    metrics.offers_upserted += transformed.rows.count
                    metrics.countries_written += transformed.countryCount
                }

                let next = Date().addingTimeInterval(Double(staleDays) * 86400)
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
                try await rpc.upsert(
                    "provider_availability_refresh_state",
                    rows: [refresh],
                    onConflict: "media_type,media_id,source_name"
                )

                metrics.stale_soft_expired += try await countSoftStaleRows(
                    rpc: rpc,
                    mediaType: mediaType,
                    mediaId: mediaId,
                    graceDays: graceDays
                )
                metrics.processed += 1
            } catch {
                metrics.api_errors += 1
                let retry = (try? await fetchRefreshState(rpc: rpc, mediaType: mediaType, mediaId: mediaId)?.retry_count) ?? 0
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
                try? await rpc.upsert(
                    "provider_availability_refresh_state",
                    rows: [refresh],
                    onConflict: "media_type,media_id,source_name"
                )
            }
        }

        metrics.finished_at = nowISO8601()
        metrics.duration_ms = Int(Date().timeIntervalSince(start) * 1000)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = metrics.finished_at
            .replacingOccurrences(of: ":", with: "-")
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
        status.queue_summary = (try? await fetchQueueSummary(rpc: rpc)) ?? status.queue_summary

        let statusData = try JSONEncoder.providerWorker.encode(status)
        try writeText(String(decoding: statusData, as: UTF8.self), to: statusPath)

        try writeUnresolvedReport(unresolved, reportDir: reportDir)
    }

    static func fetchMediaSeed(rpc: RPCClient, mediaType: String, mediaId: Int) async throws -> MediaSeed {
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

    static func fetchRefreshState(rpc: RPCClient, mediaType: String, mediaId: Int) async throws -> RefreshStateRow? {
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

    static func fetchQueueSummary(rpc: RPCClient) async throws -> QueueSummary {
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

    static func resolveSourceId(
        rpc: RPCClient,
        watchmode: WatchmodeClient,
        seed: MediaSeed,
        mediaType: String,
        mediaId: Int,
        unresolved: inout [UnresolvedEntry],
        mappedCounter: inout Int,
        unresolvedCounter: inout Int
    ) async throws -> String? {
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
        if let existingId = existing.first?.source_media_id, !existingId.isEmpty {
            return existingId
        }

        var localTitles: [String] = [seed.title_english, seed.title_romaji, seed.title_native]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        localTitles = Array(NSOrderedSet(array: localTitles)) as? [String] ?? localTitles

        guard !localTitles.isEmpty else {
            unresolved.append(UnresolvedEntry(mediaType: mediaType, mediaId: mediaId, title: "Unknown", reason: "missing_title"))
            unresolvedCounter += 1
            try await upsertSourceMap(
                rpc: rpc,
                row: SourceMapUpsert(
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
            let hits = try await watchmode.searchTitles(title)
            for hit in hits.prefix(20) {
                hitsByID[hit.id] = hit
            }
        }

        let hits = Array(hitsByID.values)
        guard !hits.isEmpty else {
            unresolved.append(UnresolvedEntry(mediaType: mediaType, mediaId: mediaId, title: localTitles[0], reason: "no_candidates"))
            unresolvedCounter += 1
            try await upsertSourceMap(
                rpc: rpc,
                row: SourceMapUpsert(
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
            try await upsertSourceMap(
                rpc: rpc,
                row: SourceMapUpsert(
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
        try await upsertSourceMap(rpc: rpc, row: row)
        mappedCounter += 1
        return top.hit.id
    }

    static func upsertSourceMap(rpc: RPCClient, row: SourceMapUpsert) async throws {
        try await rpc.upsert(
            "provider_source_map",
            rows: [row],
            onConflict: "media_type,media_id,source_name"
        )
    }

    static func scoreHits(hits: [WatchmodeSearchHit], localTitles: [String], localYear: Int?) -> [ScoredHit] {
        let scored = hits.map { hit -> ScoredHit in
            var best = 0.0
            for local in localTitles {
                best = max(best, similarity(local, hit.title))
            }
            if let localYear, let hitYear = hit.year, abs(localYear - hitYear) > 2 {
                best -= 0.08
            }
            return ScoredHit(hit: hit, score: max(0, min(1, best)))
        }
        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.hit.id < rhs.hit.id
        }
    }

    static func transformOffers(
        offers: [[String: Any]],
        mediaType: String,
        mediaId: Int,
        services: [StreamingServiceRecord]
    ) -> (rows: [AvailabilityUpsert], countryCount: Int) {
        var aggregate: [AvailabilityKey: AvailabilityAggregate] = [:]

        for offer in offers {
            let providerName = (offer["name"] as? String)
                ?? (offer["source_name"] as? String)
                ?? (offer["source"] as? String)
                ?? ""
            guard !providerName.isEmpty else { continue }

            guard let mappedService = mapProvider(providerName: providerName, services: services) else {
                continue
            }

            let countryCode = parseCountryCode(offer["region"])
                ?? parseCountryCode(offer["country"])
                ?? parseCountryCode(offer["country_code"])
            guard let countryCode else { continue }

            let availabilityType = normalizeAvailabilityType(offer["type"] as? String)

            let audio = Set(
                parseLanguageArray(offer["audio_languages"]) +
                parseLanguageArray(offer["audio_language"]) +
                parseLanguageArray(offer["language"])
            )
            let subtitles = Set(
                parseLanguageArray(offer["subtitle_languages"]) +
                parseLanguageArray(offer["subtitles"]) +
                parseLanguageArray(offer["subtitle_language"])
            )

            let deepLink = (offer["ios_url"] as? String)
                ?? (offer["android_url"] as? String)
                ?? (offer["deep_link_url"] as? String)
            let webURL = (offer["web_url"] as? String)
                ?? (offer["url"] as? String)

            let sourceOfferID: String?
            if let sourceID = offer["source_id"] as? Int {
                sourceOfferID = String(sourceID)
            } else if let sourceID = offer["source_id"] as? String {
                sourceOfferID = sourceID
            } else if let id = offer["id"] as? Int {
                sourceOfferID = String(id)
            } else if let id = offer["id"] as? String {
                sourceOfferID = id
            } else {
                sourceOfferID = nil
            }

            let key = AvailabilityKey(
                mediaType: mediaType,
                mediaId: mediaId,
                providerSlug: mappedService.slug,
                countryCode: countryCode,
                availabilityType: availabilityType
            )

            var current = aggregate[key] ?? AvailabilityAggregate(
                audioLangs: [],
                subtitleLangs: [],
                deepLinkURL: nil,
                webURL: nil,
                sourceOfferID: nil
            )
            current.audioLangs.formUnion(audio)
            current.subtitleLangs.formUnion(subtitles)
            if current.deepLinkURL == nil { current.deepLinkURL = sanitizeURL(deepLink) }
            if current.webURL == nil { current.webURL = sanitizeURL(webURL) }
            if current.sourceOfferID == nil { current.sourceOfferID = sourceOfferID }
            aggregate[key] = current
        }

        let now = nowISO8601()
        let rows = aggregate.map { key, value in
            AvailabilityUpsert(
                media_type: key.mediaType,
                media_id: key.mediaId,
                provider_slug: key.providerSlug,
                country_code: key.countryCode,
                availability_type: key.availabilityType,
                audio_langs: value.audioLangs.sorted(),
                subtitle_langs: value.subtitleLangs.sorted(),
                deep_link_url: sanitizeURL(value.deepLinkURL),
                web_url: sanitizeURL(value.webURL),
                source_name: "watchmode",
                source_offer_id: value.sourceOfferID,
                last_seen_at: now,
                updated_at: now
            )
        }

        return (rows.sorted { lhs, rhs in
            if lhs.provider_slug != rhs.provider_slug { return lhs.provider_slug < rhs.provider_slug }
            if lhs.country_code != rhs.country_code { return lhs.country_code < rhs.country_code }
            return lhs.availability_type < rhs.availability_type
        }, aggregate.count)
    }

    static func mapProvider(providerName: String, services: [StreamingServiceRecord]) -> StreamingServiceRecord? {
        let normalized = providerName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        var best: (service: StreamingServiceRecord, patternLength: Int)? = nil
        for service in services where service.is_active {
            for pattern in service.site_patterns {
                let p = pattern.lowercased()
                guard !p.isEmpty, normalized.contains(p) else { continue }
                if let current = best {
                    if service.priority < current.service.priority {
                        best = (service, p.count)
                    } else if service.priority == current.service.priority, p.count > current.patternLength {
                        best = (service, p.count)
                    }
                } else {
                    best = (service, p.count)
                }
            }
        }
        return best?.service
    }

    static func normalizeAvailabilityType(_ raw: String?) -> String {
        guard let raw else { return "subscription" }
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("free") { return "free" }
        if lower.contains("buy") || lower.contains("purchase") { return "purchase" }
        if lower.contains("rent") { return "rent" }
        if lower.contains("add") || lower.contains("channel") { return "addon" }
        return "subscription"
    }

    static func sanitizeURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        return trimmed
    }

    static func countSoftStaleRows(rpc: RPCClient, mediaType: String, mediaId: Int, graceDays: Int) async throws -> Int {
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

    static func writeUnresolvedReport(_ unresolved: [UnresolvedEntry], reportDir: String) throws {
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
}
