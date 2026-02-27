import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct SafetyCandidate: Decodable {
    let media_type: String
    let media_id: Int
    let title: String
    let title_english: String?
    let title_romaji: String?
    let title_native: String?
    let source_description: String?
    let source_description_normalized: String?
    let genres: [String]?
    let source_hash: String?
}

struct SafetyTerm: Decodable {
    let term: String
    let language: String
    let match_type: String
    let weight: Int
    let category: String
}

struct BacklogCountRow: Decodable {
    let backlog_count: Int
}

struct OpenGapRow: Decodable {
    let media_type: String
    let media_id: Int
    let title: String
    let decision_state: String
    let model_label: String?
    let model_confidence: Double?
    let rule_hits: [String]?
    let reason_codes: [String]?
    let suggested_lexicon: [String]?
    let last_scanned_at: String?
}

struct SafetyDecision {
    let state: String
    let blocked: Bool
    let ruleHits: [String]
    let reasonCodes: [String]
    let modelLabel: String?
    let modelConfidence: Double?
    let modelRationale: String?
    let suggestedLexicon: [String]
}

struct RunMetrics: Codable {
    var started_at: String
    var finished_at: String
    var processed: Int
    var blocked: Int
    var safe: Int
    var uncertain: Int
    var failed: Int
    var blocked_by_rules: Int
    var blocked_by_model: Int
    var safe_fallback_no_signal: Int
    var model_used: Int
    var model_unavailable: Int
    var avg_latency_ms: Int
    var backlog_due_before: Int
    var backlog_due_after: Int
    var open_gaps_count: Int
    var open_gaps_fetch_failed: Int
}

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

extension JSONDecoder {
    static var workerDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var workerEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
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

func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func normalizeText(_ text: String) -> String {
    text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func compactReason(_ error: Error) -> String {
    let text = String(describing: error)
    return String(text.prefix(180))
}

func regexEscape(_ value: String) -> String {
    NSRegularExpression.escapedPattern(for: value)
}

func tokenized(_ text: String) -> Set<String> {
    let cleaned = normalizeText(text)
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
    return Set(cleaned.split(separator: " ").map(String.init))
}

func buildSearchText(for candidate: SafetyCandidate) -> String {
    var fields: [String] = []
    fields.append(candidate.title)
    if let titleEnglish = candidate.title_english { fields.append(titleEnglish) }
    if let titleRomaji = candidate.title_romaji { fields.append(titleRomaji) }
    if let titleNative = candidate.title_native { fields.append(titleNative) }
    if let normalized = candidate.source_description_normalized, !normalized.isEmpty {
        fields.append(normalized)
    } else if let source = candidate.source_description {
        fields.append(source)
    }
    if let genres = candidate.genres, !genres.isEmpty {
        fields.append(genres.joined(separator: " "))
    }
    return normalizeText(fields.joined(separator: " "))
}

func matchRule(term: SafetyTerm, normalizedText: String, tokenSet: Set<String>) -> Bool {
    let query = term.term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return false }

    switch term.match_type {
    case "contains":
        return normalizedText.localizedCaseInsensitiveContains(query)
    case "exact":
        let normalizedQuery = normalizeText(query).lowercased()
        if normalizedQuery.contains(" ") {
            let boundaryPattern = "(?<![\\p{L}\\p{N}])\(regexEscape(normalizedQuery))(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: boundaryPattern, options: [.caseInsensitive]) else {
                return normalizedText.lowercased().contains(normalizedQuery)
            }
            let range = NSRange(normalizedText.startIndex..<normalizedText.endIndex, in: normalizedText)
            return regex.firstMatch(in: normalizedText, options: [], range: range) != nil
        }
        return tokenSet.contains(normalizedQuery)
    case "regex":
        guard let regex = try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(normalizedText.startIndex..<normalizedText.endIndex, in: normalizedText)
        return regex.firstMatch(in: normalizedText, options: [], range: range) != nil
    default:
        return false
    }
}

func evaluateRules(candidate: SafetyCandidate, terms: [SafetyTerm]) -> (hits: [String], categories: [String], score: Int) {
    let searchText = buildSearchText(for: candidate)
    let normalized = searchText.lowercased()
    let tokens = tokenized(searchText)
    var hits: [String] = []
    var categories: [String] = []
    var score = 0

    for term in terms {
        if matchRule(term: term, normalizedText: normalized, tokenSet: tokens) {
            hits.append("\(term.category):\(term.term)")
            categories.append(term.category)
            score += term.weight
        }
    }

    return (hits, categories, score)
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

func decideSafety(
    candidate: SafetyCandidate,
    terms: [SafetyTerm],
    minBlockedConfidence: Double,
    minSafeConfidence: Double,
    safeFallbackMaxRuleScore: Int
) async -> (decision: SafetyDecision, modelUsed: Bool, modelAvailable: Bool) {
    let ruleResult = evaluateRules(candidate: candidate, terms: terms)
    let strongRuleHit = ruleResult.score >= 250 || ruleResult.categories.contains("porn_core")

    if strongRuleHit {
        let decision = SafetyDecision(
            state: "blocked",
            blocked: true,
            ruleHits: ruleResult.hits,
            reasonCodes: ["rules_high_confidence"],
            modelLabel: nil,
            modelConfidence: nil,
            modelRationale: nil,
            suggestedLexicon: []
        )
        return (decision, false, false)
    }

    let model = await modelDecision(for: candidate)
    var reasonCodes: [String] = []

    if model.available {
        if model.label == "blocked" && model.confidence >= minBlockedConfidence {
            reasonCodes.append("model_blocked")
            if !ruleResult.hits.isEmpty { reasonCodes.append("rules_supporting") }
            let decision = SafetyDecision(
                state: "blocked",
                blocked: true,
                ruleHits: ruleResult.hits,
                reasonCodes: reasonCodes,
                modelLabel: model.label,
                modelConfidence: model.confidence,
                modelRationale: model.rationale,
                suggestedLexicon: model.suggestedTerms
            )
            return (decision, true, true)
        }

        if model.label == "safe" && model.confidence >= minSafeConfidence && ruleResult.score < 120 {
            let decision = SafetyDecision(
                state: "safe",
                blocked: false,
                ruleHits: ruleResult.hits,
                reasonCodes: ["model_safe"],
                modelLabel: model.label,
                modelConfidence: model.confidence,
                modelRationale: model.rationale,
                suggestedLexicon: model.suggestedTerms
            )
            return (decision, true, true)
        }

        reasonCodes.append("model_uncertain")
        // If model cannot confidently classify but rules show no meaningful porn signal,
        // default to safe to prevent an ever-growing uncertain queue.
        if ruleResult.score <= safeFallbackMaxRuleScore && ruleResult.hits.isEmpty {
            let decision = SafetyDecision(
                state: "safe",
                blocked: false,
                ruleHits: ruleResult.hits,
                reasonCodes: ["fallback_safe_no_signal"],
                modelLabel: model.label,
                modelConfidence: model.confidence,
                modelRationale: model.rationale,
                suggestedLexicon: model.suggestedTerms
            )
            return (decision, true, true)
        }
    } else {
        reasonCodes.append("model_unavailable")
        // During model outages, keep pipeline moving when there is no porn signal.
        if ruleResult.score <= safeFallbackMaxRuleScore && ruleResult.hits.isEmpty {
            let decision = SafetyDecision(
                state: "safe",
                blocked: false,
                ruleHits: ruleResult.hits,
                reasonCodes: ["fallback_safe_no_signal", "model_unavailable"],
                modelLabel: nil,
                modelConfidence: nil,
                modelRationale: nil,
                suggestedLexicon: []
            )
            return (decision, false, false)
        }
    }

    if ruleResult.score >= 140 {
        reasonCodes.append("rules_moderate_signal")
    } else if ruleResult.hits.isEmpty {
        reasonCodes.append("no_strong_signal")
    }

    let decision = SafetyDecision(
        state: "uncertain",
        blocked: false,
        ruleHits: ruleResult.hits,
        reasonCodes: reasonCodes,
        modelLabel: model.available ? model.label : nil,
        modelConfidence: model.available ? model.confidence : nil,
        modelRationale: model.available ? model.rationale : nil,
        suggestedLexicon: model.suggestedTerms
    )
    return (decision, model.available, model.available)
}

func buildUncertainMarkdown(generatedAt: String, rows: [OpenGapRow]) -> String {
    var lines: [String] = []
    lines.append("# Catalog Safety Open Gaps")
    lines.append("")
    lines.append("- Generated at: \(generatedAt)")
    lines.append("- Decision state: uncertain")
    lines.append("- Count: \(rows.count)")
    lines.append("")
    lines.append("| Media | ID | Title | Model | Confidence | Rule hits | Reason | Suggested lexicon | Last scanned |")
    lines.append("| --- | ---: | --- | --- | ---: | --- | --- | --- | --- |")

    for row in rows {
        let title = row.title.replacingOccurrences(of: "|", with: "\\|")
        let model = (row.model_label ?? "-").replacingOccurrences(of: "|", with: "\\|")
        let confidence = row.model_confidence.map { String(format: "%.3f", $0) } ?? "-"
        let hits = (row.rule_hits ?? []).joined(separator: ", ").replacingOccurrences(of: "|", with: "\\|")
        let reason = (row.reason_codes ?? []).joined(separator: ", ").replacingOccurrences(of: "|", with: "\\|")
        let suggested = (row.suggested_lexicon ?? []).joined(separator: ", ").replacingOccurrences(of: "|", with: "\\|")
        let scanned = row.last_scanned_at ?? "-"
        lines.append("| \(row.media_type) | \(row.media_id) | \(title) | \(model) | \(confidence) | \(hits.isEmpty ? "-" : hits) | \(reason.isEmpty ? "-" : reason) | \(suggested.isEmpty ? "-" : suggested) | \(scanned) |")
    }

    lines.append("")
    lines.append("## Suggested Lexicon Additions")
    let suggestionCounts = rows
        .flatMap { $0.suggested_lexicon ?? [] }
        .map { $0.lowercased() }
        .reduce(into: [String: Int]()) { result, value in
            result[value, default: 0] += 1
        }
    let topSuggestions = suggestionCounts.sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key < rhs.key
    }

    if topSuggestions.isEmpty {
        lines.append("- None from current open gaps.")
    } else {
        for (term, count) in topSuggestions.prefix(20) {
            lines.append("- \(term) (\(count))")
        }
    }
    lines.append("")
    return lines.joined(separator: "\n")
}

func appendWorkerLog(reportsRoot: URL, message: String) {
    let logURL = reportsRoot.appendingPathComponent("worker.log")
    let line = "[\(isoNow())] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }

    if FileManager.default.fileExists(atPath: logURL.path),
       let handle = try? FileHandle(forWritingTo: logURL) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
        return
    }

    try? data.write(to: logURL, options: .atomic)
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
        let reportsRoot = URL(fileURLWithPath: stringEnv("CATALOG_SAFETY_REPORTS_DIR", default: "/Applications/Kuro/reports/catalog-safety"), isDirectory: true)

        try FileManager.default.createDirectory(at: reportsRoot, withIntermediateDirectories: true)

        let startedDate = Date()
        let client = RPCClient(baseURL: baseURL, serviceRoleKey: serviceRoleKey)
        let terms = try await client.fetchSafetyTerms()

        var metrics = RunMetrics(
            started_at: isoNow(),
            finished_at: isoNow(),
            processed: 0,
            blocked: 0,
            safe: 0,
            uncertain: 0,
            failed: 0,
            blocked_by_rules: 0,
            blocked_by_model: 0,
            safe_fallback_no_signal: 0,
            model_used: 0,
            model_unavailable: 0,
            avg_latency_ms: 0,
            backlog_due_before: 0,
            backlog_due_after: 0,
            open_gaps_count: 0,
            open_gaps_fetch_failed: 0
        )

        var latencySamples: [Int] = []

        for mediaType in mediaTypes {
            let backlogRows: [BacklogCountRow] = try await client.rpc(
                "get_catalog_safety_backlog_count",
                payload: ["p_media_type": mediaType],
                as: [BacklogCountRow].self
            )
            metrics.backlog_due_before += backlogRows.first?.backlog_count ?? 0
        }

        for mediaType in mediaTypes {
            let candidates: [SafetyCandidate] = try await client.rpc(
                "get_catalog_safety_candidates",
                payload: ["p_media_type": mediaType, "p_limit": batchSize],
                as: [SafetyCandidate].self
            )

            for candidate in candidates {
                metrics.processed += 1
                let started = Date()
                do {
                    let evaluatedRules = evaluateRules(candidate: candidate, terms: terms)
                    let resolved = await decideSafety(
                        candidate: candidate,
                        terms: terms,
                        minBlockedConfidence: minBlockedConfidence,
                        minSafeConfidence: minSafeConfidence,
                        safeFallbackMaxRuleScore: safeFallbackMaxRuleScore
                    )

                    let decision = resolved.decision
                    if resolved.modelUsed { metrics.model_used += 1 }
                    if !resolved.modelAvailable { metrics.model_unavailable += 1 }

                    if decision.state == "blocked" {
                        metrics.blocked += 1
                        if decision.reasonCodes.contains("rules_high_confidence") {
                            metrics.blocked_by_rules += 1
                        } else if decision.reasonCodes.contains("model_blocked") {
                            metrics.blocked_by_model += 1
                        } else if evaluatedRules.score >= 250 {
                            metrics.blocked_by_rules += 1
                        }
                    } else if decision.state == "safe" {
                        metrics.safe += 1
                        if decision.reasonCodes.contains("fallback_safe_no_signal") {
                            metrics.safe_fallback_no_signal += 1
                        }
                    } else {
                        metrics.uncertain += 1
                    }

                    var payload: [String: Any] = [
                        "p_media_type": candidate.media_type,
                        "p_media_id": candidate.media_id,
                        "p_decision_state": decision.state,
                        "p_blocked": decision.blocked,
                        "p_rule_hits": decision.ruleHits,
                        "p_reason_codes": decision.reasonCodes,
                        "p_suggested_lexicon": decision.suggestedLexicon
                    ]
                    if let modelLabel = decision.modelLabel, !modelLabel.isEmpty {
                        payload["p_model_label"] = modelLabel
                    }
                    if let modelConfidence = decision.modelConfidence {
                        payload["p_model_confidence"] = modelConfidence
                    }
                    if let modelRationale = decision.modelRationale, !modelRationale.isEmpty {
                        payload["p_model_rationale"] = modelRationale
                    }
                    if let sourceHash = candidate.source_hash, !sourceHash.isEmpty {
                        payload["p_source_hash"] = sourceHash
                    }

                    try await client.rpcNoContent("upsert_catalog_safety_result", payload: payload)
                } catch {
                    metrics.failed += 1
                    try? await client.rpcNoContent(
                        "mark_catalog_safety_failed",
                        payload: [
                            "p_media_type": candidate.media_type,
                            "p_media_id": candidate.media_id,
                            "p_reason": compactReason(error)
                        ]
                    )
                }
                let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
                latencySamples.append(elapsedMs)
            }
        }

        for mediaType in mediaTypes {
            let backlogRows: [BacklogCountRow] = try await client.rpc(
                "get_catalog_safety_backlog_count",
                payload: ["p_media_type": mediaType],
                as: [BacklogCountRow].self
            )
            metrics.backlog_due_after += backlogRows.first?.backlog_count ?? 0
        }

        var openGaps: [OpenGapRow] = []
        do {
            openGaps = try await client.rpc(
                "get_catalog_safety_open_gaps",
                payload: ["p_limit": openGapLimit],
                as: [OpenGapRow].self
            )
        } catch {
            metrics.open_gaps_fetch_failed += 1
            appendWorkerLog(
                reportsRoot: reportsRoot,
                message: "open gaps fetch failed: \(compactReason(error))"
            )
        }

        metrics.open_gaps_count = openGaps.count
        metrics.finished_at = isoNow()
        if !latencySamples.isEmpty {
            metrics.avg_latency_ms = latencySamples.reduce(0, +) / latencySamples.count
        }

        let statusData = try JSONEncoder.workerEncoder.encode(metrics)
        try statusData.write(to: reportsRoot.appendingPathComponent("latest-status.json"), options: .atomic)

        let runName = ISO8601DateFormatter().string(from: startedDate).replacingOccurrences(of: ":", with: "-")
        let runLogURL = reportsRoot.appendingPathComponent("run-\(runName).log")
        let summary = "processed=\(metrics.processed) blocked=\(metrics.blocked) safe=\(metrics.safe) uncertain=\(metrics.uncertain) failed=\(metrics.failed) blocked_by_rules=\(metrics.blocked_by_rules) blocked_by_model=\(metrics.blocked_by_model) safe_fallback_no_signal=\(metrics.safe_fallback_no_signal) model_used=\(metrics.model_used) model_unavailable=\(metrics.model_unavailable) avg_latency_ms=\(metrics.avg_latency_ms) backlog_due_before=\(metrics.backlog_due_before) backlog_due_after=\(metrics.backlog_due_after) open_gaps_count=\(metrics.open_gaps_count) open_gaps_fetch_failed=\(metrics.open_gaps_fetch_failed)"
        try summary.appending("\n").write(to: runLogURL, atomically: true, encoding: .utf8)

        let latestUncertainURL = reportsRoot.appendingPathComponent("uncertain-latest.md")
        let runUncertainURL = reportsRoot.appendingPathComponent("uncertain-\(runName).md")
        if metrics.open_gaps_fetch_failed == 0 {
            let uncertainMarkdown = buildUncertainMarkdown(generatedAt: metrics.finished_at, rows: openGaps)
            try uncertainMarkdown.write(
                to: latestUncertainURL,
                atomically: true,
                encoding: .utf8
            )
            try uncertainMarkdown.write(
                to: runUncertainURL,
                atomically: true,
                encoding: .utf8
            )
        } else if let previousReport = try? String(contentsOf: latestUncertainURL, encoding: .utf8), !previousReport.isEmpty {
            // Preserve latest uncertain snapshot if this run couldn't fetch open gaps.
            try previousReport.write(
                to: runUncertainURL,
                atomically: true,
                encoding: .utf8
            )
        } else {
            let fallbackReport = """
            # Catalog Safety Open Gaps

            - Generated at: \(metrics.finished_at)
            - Decision state: uncertain
            - Count: unavailable
            - Note: get_catalog_safety_open_gaps failed in this run; no prior report available.
            """
            try fallbackReport.write(
                to: runUncertainURL,
                atomically: true,
                encoding: .utf8
            )
        }

        if let statusText = String(data: statusData, encoding: .utf8) {
            print(statusText)
        }
    }
}
