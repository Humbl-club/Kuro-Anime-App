import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum WorkerError: Error, CustomStringConvertible {
    case missingEnv(String)
    case invalidResponse(String)

    var description: String {
        switch self {
        case .missingEnv(let key): return "Missing env var: \(key)"
        case .invalidResponse(let message): return message
        }
    }
}

struct RPCClient {
    let baseURL: URL
    let serviceRoleKey: String

    func rpc<T: Decodable>(_ name: String, payload: [String: Any], as _: T.Type) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(serviceRoleKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(serviceRoleKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WorkerError.invalidResponse("RPC \(name) returned non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw WorkerError.invalidResponse("RPC \(name) failed with \(http.statusCode): \(body)")
        }
        return try JSONDecoder.workerDecoder.decode(T.self, from: data)
    }

    func rpcNoContent(_ name: String, payload: [String: Any]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(serviceRoleKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(serviceRoleKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WorkerError.invalidResponse("RPC \(name) returned non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw WorkerError.invalidResponse("RPC \(name) failed with \(http.statusCode): \(body)")
        }
    }

    func fetchSafetyTerms() async throws -> [SafetyTerm] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/catalog_safety_terms"), resolvingAgainstBaseURL: false) else {
            throw WorkerError.invalidResponse("Failed to build URL components for catalog_safety_terms")
        }
        components.queryItems = [
            URLQueryItem(name: "select", value: "term,language,match_type,weight,category"),
            URLQueryItem(name: "active", value: "eq.true"),
            URLQueryItem(name: "order", value: "weight.desc,id.asc")
        ]
        guard let url = components.url else {
            throw WorkerError.invalidResponse("Failed to build URL for catalog_safety_terms")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(serviceRoleKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(serviceRoleKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WorkerError.invalidResponse("catalog_safety_terms returned non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw WorkerError.invalidResponse("catalog_safety_terms failed with \(http.statusCode): \(body)")
        }

        return try JSONDecoder.workerDecoder.decode([SafetyTerm].self, from: data)
    }
}

extension RPCClient: CatalogSafetyStore {
    func backlogCount(mediaType: String) async throws -> Int {
        let rows: [BacklogCountRow] = try await rpc(
            "get_catalog_safety_backlog_count",
            payload: ["p_media_type": mediaType],
            as: [BacklogCountRow].self
        )
        return rows.first?.backlog_count ?? 0
    }

    func candidates(mediaType: String, limit: Int) async throws -> [SafetyCandidate] {
        try await rpc(
            "get_catalog_safety_candidates",
            payload: ["p_media_type": mediaType, "p_limit": limit],
            as: [SafetyCandidate].self
        )
    }

    func safetyTerms() async throws -> [SafetyTerm] {
        try await fetchSafetyTerms()
    }

    func writeDecision(_ payload: [String: Any]) async throws {
        try await rpcNoContent("upsert_catalog_safety_result", payload: payload)
    }

    func markFailed(mediaType: String, mediaId: Int, reason: String) async throws {
        try await rpcNoContent(
            "mark_catalog_safety_failed",
            payload: [
                "p_media_type": mediaType,
                "p_media_id": mediaId,
                "p_reason": reason
            ]
        )
    }

    func openGaps(limit: Int) async throws -> [OpenGapRow] {
        try await rpc(
            "get_catalog_safety_open_gaps",
            payload: ["p_limit": limit],
            as: [OpenGapRow].self
        )
    }
}

extension JSONDecoder {
    static var workerDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

func intEnv(_ key: String, default defaultValue: Int) -> Int {
    guard let raw = ProcessInfo.processInfo.environment[key], let value = Int(raw) else {
        return defaultValue
    }
    return value
}

func stringEnv(_ key: String, default defaultValue: String) -> String {
    ProcessInfo.processInfo.environment[key] ?? defaultValue
}

func mediaTypesFromEnv() -> [String] {
    let raw = stringEnv("CATALOG_SAFETY_MEDIA_TYPES", default: "ANIME,MANGA")
    let parsed = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        .filter { $0 == "ANIME" || $0 == "MANGA" }
    return parsed.isEmpty ? ["ANIME", "MANGA"] : parsed
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct SafetyModelOutput {
    @Guide(description: "Decision label. Must be one of: blocked, safe, uncertain")
    var label: String

    @Guide(description: "Confidence as a number between 0 and 1, represented as text (example: 0.83)")
    var confidence: String

    @Guide(description: "One short rationale")
    var rationale: String

    @Guide(description: "Comma-separated suggested keyword additions for future lexicon improvements")
    var suggested_terms: String
}
#endif

func modelDecision(for candidate: SafetyCandidate) async -> (label: String, confidence: Double, rationale: String, suggestedTerms: [String], available: Bool) {
    #if canImport(FoundationModels)
    if #available(macOS 26, *), SystemLanguageModel.default.isAvailable {
        let prompt = """
        You are a catalog safety classifier for an anime/manga app.
        Task: classify whether this title should be blocked for explicit pornography content.

        Rules:
        - blocked: clear explicit pornographic sexual content (including hentai pornography).
        - safe: no explicit pornography intent.
        - uncertain: ambiguous/conflicting signals where pornography risk cannot be determined.
        - Focus on pornography filtering only (not general violence).
        - IMPORTANT: If there are no explicit sexual/porn indicators in title/genres/description, choose safe (not uncertain).

        Return:
        - label: blocked | safe | uncertain
        - confidence: 0..1
        - rationale: concise
        - suggested_terms: comma-separated terms that would improve rule-based filtering.

        Title: \(candidate.title)
        English title: \(candidate.title_english ?? "")
        Romaji title: \(candidate.title_romaji ?? "")
        Native title: \(candidate.title_native ?? "")
        Genres: \((candidate.genres ?? []).joined(separator: ", "))
        Description: \(normalizeText(candidate.source_description_normalized ?? candidate.source_description ?? ""))
        """

        do {
            let session = LanguageModelSession()
            let output = try await session.respond(to: prompt, generating: SafetyModelOutput.self).content
            let rawLabel = output.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedLabel: String
            if rawLabel == "blocked" || rawLabel == "safe" || rawLabel == "uncertain" {
                normalizedLabel = rawLabel
            } else {
                normalizedLabel = "uncertain"
            }
            let confidence = max(0.0, min(1.0, Double(output.confidence.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0))
            let rationale = output.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
            let suggestions = output.suggested_terms
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return (normalizedLabel, confidence, rationale, suggestions, true)
        } catch {
            return ("uncertain", 0.0, "model_error", [], true)
        }
    }
    #endif

    return ("uncertain", 0.0, "model_unavailable", [], false)
}

func liveCatalogSafetyModel(_ candidate: SafetyCandidate) async -> CatalogSafetyModelResult {
    let model = await modelDecision(for: candidate)
    return CatalogSafetyModelResult(
        label: model.label,
        confidence: model.confidence,
        rationale: model.rationale,
        suggestedTerms: model.suggestedTerms,
        available: model.available
    )
}

@main
struct CatalogSafetyWorker {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("[catalog-safety-worker] fatal: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let supabaseURLRaw = env["SUPABASE_URL"], !supabaseURLRaw.isEmpty else {
            throw WorkerError.missingEnv("SUPABASE_URL")
        }
        guard let serviceRoleKey = env["SUPABASE_SERVICE_ROLE_KEY"], !serviceRoleKey.isEmpty else {
            throw WorkerError.missingEnv("SUPABASE_SERVICE_ROLE_KEY")
        }
        guard let baseURL = URL(string: supabaseURLRaw) else {
            throw WorkerError.invalidResponse("Invalid SUPABASE_URL: \(supabaseURLRaw)")
        }

        let batchSize = max(1, min(1000, intEnv("CATALOG_SAFETY_BATCH_SIZE", default: 200)))
        let openGapLimit = max(20, min(2000, intEnv("CATALOG_SAFETY_OPEN_GAPS_LIMIT", default: 400)))
        let minBlockedConfidence = max(0.50, min(0.99, Double(stringEnv("CATALOG_SAFETY_MODEL_BLOCKED_CONFIDENCE", default: "0.78")) ?? 0.78))
        let minSafeConfidence = max(0.50, min(0.99, Double(stringEnv("CATALOG_SAFETY_MODEL_SAFE_CONFIDENCE", default: "0.70")) ?? 0.70))
        let safeFallbackMaxRuleScore = max(0, min(200, Int(stringEnv("CATALOG_SAFETY_SAFE_FALLBACK_MAX_RULE_SCORE", default: "40")) ?? 40))
        let mediaTypes = mediaTypesFromEnv()
        let reportsRoot = URL(fileURLWithPath: stringEnv("CATALOG_SAFETY_REPORTS_DIR", default: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("reports/catalog-safety").path), isDirectory: true)
        let client = RPCClient(baseURL: baseURL, serviceRoleKey: serviceRoleKey)

        _ = try await runCatalogSafety(
            mediaTypes: mediaTypes,
            batchSize: batchSize,
            openGapLimit: openGapLimit,
            minBlockedConfidence: minBlockedConfidence,
            minSafeConfidence: minSafeConfidence,
            safeFallbackMaxRuleScore: safeFallbackMaxRuleScore,
            classify: liveCatalogSafetyModel,
            store: client,
            reportsRoot: reportsRoot
        )
    }
}
