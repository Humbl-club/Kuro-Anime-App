import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct BacklogCountRow: Decodable {
    let backlog_count: Int
}

enum WorkerError: Error, CustomStringConvertible {
    case missingEnv(String)
    case invalidResponse(String)

    var description: String {
        switch self {
        case .missingEnv(let key): return "Missing env var: \(key)"
        case .invalidResponse(let msg): return msg
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
            throw WorkerError.invalidResponse("RPC \(name) returned a non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw WorkerError.invalidResponse("RPC \(name) failed with \(http.statusCode): \(body)")
        }

        return try JSONDecoder.enrichmentDecoder.decode(T.self, from: data)
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
            throw WorkerError.invalidResponse("RPC \(name) returned a non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw WorkerError.invalidResponse("RPC \(name) failed with \(http.statusCode): \(body)")
        }
    }
}

extension RPCClient: SynopsisStore {
    func backlogCount(mediaType: String) async throws -> Int {
        let rows: [BacklogCountRow] = try await rpc(
            "get_synopsis_enrichment_backlog_count",
            payload: ["p_media_type": mediaType],
            as: [BacklogCountRow].self
        )
        return rows.first?.backlog_count ?? 0
    }

    func candidates(mediaType: String, limit: Int) async throws -> [Candidate] {
        try await rpc(
            "get_synopsis_enrichment_candidates",
            payload: ["p_media_type": mediaType, "p_limit": limit],
            as: [Candidate].self
        )
    }

    func markFailed(mediaType: String, mediaId: Int, reason: String) async throws {
        try await rpcNoContent(
            "mark_synopsis_enhanced_failed",
            payload: [
                "p_media_type": mediaType,
                "p_media_id": mediaId,
                "p_reason": reason
            ]
        )
    }

    func writeEnhanced(mediaType: String, mediaId: Int, text: String) async throws {
        try await rpcNoContent(
            "upsert_synopsis_enhanced",
            payload: [
                "p_media_type": mediaType,
                "p_media_id": mediaId,
                "p_text": text,
                "p_meta": [
                    "source": "apple_fm_local",
                    "model": "system_language_model",
                    "version": "v1.1"
                ]
            ]
        )
    }
}

extension JSONDecoder {
    static var enrichmentDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct SynopsisOutput {
    @Guide(description: "A spoiler-safe short synopsis hook for anime or manga.")
    var hook: String
}
#endif

func generateSynopsis(title: String, source: String, config: SynopsisQualityConfig) async -> String {
    #if canImport(FoundationModels)
    if #available(macOS 26, *), SystemLanguageModel.default.isAvailable {
        let prompt = """
        Rewrite this anime/manga synopsis into a spoiler-safe short intro in a curated editorial voice.
        Requirements:
        - Keep original language.
        - Tone: precise, atmospheric, restrained, cinematic, mature.
        - Write \(config.minSentences)-\(config.maxSentences) sentences.
        - Aim for roughly \(config.minChars)-\(config.maxChars) characters.
        - Cover premise, setting, and central tension clearly.
        - Do not include twists, deaths, betrayals, ending information, or major reveals.
        - Do not use rhetorical questions.
        - Do not use hype phrases like "Prepare for", "Dive into", or "Join him/her/them".
        - Avoid childish or promotional phrasing.
        - Do not include source attributions like "(Source: ...)".
        - Ensure every sentence is complete and ends naturally.

        Title: \(title)
        Source synopsis: \(normalizeText(source))
        """

        do {
            let session = LanguageModelSession()
            let output = try await session.respond(to: prompt, generating: SynopsisOutput.self).content
            let hook = output.hook.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hook.isEmpty {
                return hook
            }
        } catch {
            // Fall back to deterministic local summarization.
        }
    }
    #endif

    return heuristicSynopsis(title: title, source: source, config: config)
}

func polishSynopsisTone(title: String, source: String, draft: String, config: SynopsisQualityConfig) async -> String {
    #if canImport(FoundationModels)
    if #available(macOS 26, *), SystemLanguageModel.default.isAvailable {
        let prompt = """
        You are editing a draft anime/manga synopsis for a mature audience.
        Rewrite it in an elegant, concise editorial style.
        Requirements:
        - Keep facts faithful to the source.
        - Keep \(config.minSentences)-\(config.maxSentences) complete sentences.
        - Keep length around \(config.minChars)-\(config.maxChars) characters.
        - No rhetorical questions and no exclamation marks.
        - No hype language or childish wording.
        - No source attributions.

        Title: \(title)
        Source synopsis: \(normalizeText(source))
        Draft synopsis: \(normalizeText(draft))
        """

        do {
            let session = LanguageModelSession()
            let output = try await session.respond(to: prompt, generating: SynopsisOutput.self).content
            let hook = output.hook.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hook.isEmpty {
                return hook
            }
        } catch {
            // Fall through to draft.
        }
    }
    #endif
    return draft
}

struct LiveSynopsisProvider: SynopsisProvider {
    func generate(title: String, source: String, config: SynopsisQualityConfig) async throws -> String {
        await generateSynopsis(title: title, source: source, config: config)
    }

    func polish(title: String, source: String, draft: String, config: SynopsisQualityConfig) async throws -> String {
        await polishSynopsisTone(title: title, source: source, draft: draft, config: config)
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
    let raw = stringEnv("SYNOPSIS_MEDIA_TYPES", default: "ANIME,MANGA")
    let parsed = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        .filter { $0 == "ANIME" || $0 == "MANGA" }
    return parsed.isEmpty ? ["ANIME", "MANGA"] : parsed
}

@main
struct SynopsisEnrichmentWorker {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("[synopsis-worker] fatal: \(error)\n", stderr)
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

        let batchSize = max(1, min(200, intEnv("SYNOPSIS_BATCH_SIZE", default: 25)))
        let minChars = max(80, intEnv("SYNOPSIS_MIN_CHARS", default: 170))
        let maxChars = max(minChars + 20, intEnv("SYNOPSIS_MAX_CHARS", default: 620))
        let minSentences = max(2, intEnv("SYNOPSIS_MIN_SENTENCES", default: 3))
        let maxSentences = max(minSentences, intEnv("SYNOPSIS_MAX_SENTENCES", default: 4))
        let quality = SynopsisQualityConfig(
            minChars: minChars,
            maxChars: maxChars,
            minSentences: minSentences,
            maxSentences: maxSentences,
            minSourceChars: max(40, intEnv("SYNOPSIS_MIN_SOURCE_CHARS", default: 110))
        )
        let mediaTypes = mediaTypesFromEnv()
        let reportsRoot = URL(fileURLWithPath: stringEnv("SYNOPSIS_REPORTS_DIR", default: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("reports/synopsis-enrichment").path), isDirectory: true)
        let client = RPCClient(baseURL: baseURL, serviceRoleKey: serviceRoleKey)

        _ = try await runSynopsisEnrichment(
            mediaTypes: mediaTypes,
            batchSize: batchSize,
            quality: quality,
            provider: LiveSynopsisProvider(),
            store: client,
            reportsRoot: reportsRoot
        )
    }
}
