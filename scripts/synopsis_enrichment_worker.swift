import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct Candidate: Decodable {
    let media_type: String
    let media_id: Int
    let title: String
    let source_description: String
    let source_description_normalized: String?
    let synopsis_enhanced: String?
}

struct RunMetrics: Codable {
    var started_at: String
    var finished_at: String
    var processed: Int
    var generated: Int
    var tone_polish_used: Int
    var fallback_used: Int
    var autodeduped_sentences: Int
    var rejected_quality: Int
    var insufficient_source: Int
    var failed: Int
    var avg_latency_ms: Int
    var backlog_due_before: Int
    var backlog_due_after: Int
    var backlog_remaining_estimate: Int
}

struct BacklogCountRow: Decodable {
    let backlog_count: Int
}

struct WeakSourceEntry {
    let mediaType: String
    let mediaId: Int
    let title: String
    let sourceChars: Int
    let reason: String
}

struct GeneratedSynopsisEntry {
    let mediaType: String
    let mediaId: Int
    let title: String
    let synopsis: String
}

struct SynopsisQualityConfig {
    let minChars: Int
    let maxChars: Int
    let minSentences: Int
    let maxSentences: Int
    let minSourceChars: Int
}

struct SynopsisPostProcessResult {
    let text: String
    let dedupedCount: Int
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

extension JSONDecoder {
    static var enrichmentDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var enrichmentEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

func normalizeText(_ text: String) -> String {
    let cleaned = text
        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned
}

func containsSourceAttribution(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return false }
    if trimmed.range(of: "(?i)\\(\\s*source\\s*:[^)]+\\)", options: .regularExpression) != nil { return true }
    if trimmed.range(of: "(?i)\\bsource\\s*:\\s*[^\\.\\n]+\\.?\\s*$", options: .regularExpression) != nil { return true }
    return false
}

func splitIntoSentences(_ text: String) -> [String] {
    text.split(whereSeparator: { ".!?".contains($0) })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func extractCompleteSentences(_ text: String) -> [String] {
    let normalized = normalizeText(text)
    guard !normalized.isEmpty else { return [] }
    guard let regex = try? NSRegularExpression(pattern: #"[^.!?]+[.!?]+"#, options: []) else {
        return splitIntoSentences(normalized).map { "\($0)." }
    }
    let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
    let matches = regex.matches(in: normalized, options: [], range: range)
    return matches.compactMap { match in
        guard let r = Range(match.range, in: normalized) else { return nil }
        let sentence = normalized[r].trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? nil : sentence
    }
}

func sentenceFingerprint(_ sentence: String) -> String {
    normalizeText(sentence)
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func dedupeAndSanitizeSynopsis(_ text: String) -> (text: String, dedupedCount: Int) {
    var cleaned = normalizeText(text)
    cleaned = cleaned.replacingOccurrences(of: "(?i)\\(\\s*source\\s*:[^)]+\\)", with: "", options: .regularExpression)
    cleaned = cleaned.replacingOccurrences(of: "(?i)\\bsource\\s*:\\s*[^\\.\\n]+\\.?\\s*$", with: "", options: .regularExpression)
    cleaned = normalizeText(cleaned)

    var sourceSentences = extractCompleteSentences(cleaned)
    if sourceSentences.isEmpty {
        sourceSentences = splitIntoSentences(cleaned).map { "\($0)." }
    }

    var seen: Set<String> = []
    var kept: [String] = []
    var dedupedCount = 0

    for sentence in sourceSentences {
        let key = sentenceFingerprint(sentence)
        guard !key.isEmpty else { continue }
        if seen.contains(key) {
            dedupedCount += 1
            continue
        }
        seen.insert(key)
        kept.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    let rebuilt = kept.joined(separator: " ")
    return (normalizeText(rebuilt), dedupedCount)
}

func fitSynopsisToConstraints(_ text: String, config: SynopsisQualityConfig) -> String {
    var sentences = extractCompleteSentences(text)
    if sentences.isEmpty {
        sentences = splitIntoSentences(text).map { "\($0)." }
    }
    guard !sentences.isEmpty else { return "" }

    func joined(_ arr: [String]) -> String {
        normalizeText(arr.joined(separator: " "))
    }

    var selected: [String] = []
    for sentence in sentences {
        if selected.count >= config.maxSentences { break }
        let candidate = joined(selected + [sentence])
        if candidate.count <= config.maxChars || selected.isEmpty {
            selected.append(sentence)
        } else {
            break
        }
    }

    while selected.count > config.minSentences && joined(selected).count > config.maxChars {
        selected.removeLast()
    }

    if selected.isEmpty {
        selected = [sentences[0]]
    }

    var output = joined(selected)
    if output.count > config.maxChars {
        let maxIndex = output.index(output.startIndex, offsetBy: min(config.maxChars, output.count))
        let prefix = String(output[..<maxIndex])
        let soft = prefix.replacingOccurrences(of: "\\s+\\S*$", with: "", options: .regularExpression)
        output = normalizeText(soft)
        if !output.isEmpty && !".!?".contains(output.last!) {
            output += "."
        }
    }
    return output
}

func containsLowQualityPhrases(_ text: String) -> Bool {
    let normalized = normalizeText(text).lowercased()
    let banned = [
        "prepare for",
        "dive into",
        "discover the",
        "join him",
        "join her",
        "join them",
        "hilariously",
        "exciting adventure",
        "thrilling adventure",
        "epic showdown",
        "must-watch",
        "bonafide",
        "embarks on an epic",
        "unwavering resolve",
        "legendary history",
        "world peace is on the line"
    ]
    if banned.contains(where: { normalized.contains($0) }) { return true }
    if normalized.contains("?") { return true }
    return false
}

func postProcessSynopsis(_ text: String, config: SynopsisQualityConfig) -> SynopsisPostProcessResult {
    let deduped = dedupeAndSanitizeSynopsis(text)
    let fitted = fitSynopsisToConstraints(deduped.text, config: config)
    return SynopsisPostProcessResult(text: fitted, dedupedCount: deduped.dedupedCount)
}

func sentenceCount(in text: String) -> Int {
    splitIntoSentences(text).count
}

func hasDuplicateSentences(_ text: String) -> Bool {
    let keys = splitIntoSentences(text).map(sentenceFingerprint).filter { !$0.isEmpty }
    return Set(keys).count < keys.count
}

func bestSourceText(for candidate: Candidate) -> String {
    let primary = normalizeText(candidate.source_description)
    let normalized = normalizeText(candidate.source_description_normalized ?? "")
    return normalized.count > primary.count ? normalized : primary
}

func heuristicSynopsis(title: String, source: String, config: SynopsisQualityConfig) -> String {
    let cleaned = normalizeText(source)
    if cleaned.isEmpty { return "" }

    let sentences = cleaned
        .split(whereSeparator: { ".!?".contains($0) })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    if sentences.isEmpty {
        return String(cleaned.prefix(config.maxChars))
    }

    let targetSentences = max(config.minSentences, min(config.maxSentences, 4))
    let chosen = Array(sentences.prefix(targetSentences))
    let merged = chosen.map { "\($0)." }.joined(separator: " ")
    return String(merged.prefix(config.maxChars))
}

func passesQualityGates(candidate: Candidate, generated: String, sourceText: String, config: SynopsisQualityConfig) -> Bool {
    let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= config.minChars else { return false }
    guard trimmed.count <= config.maxChars else { return false }
    guard !containsSourceAttribution(trimmed) else { return false }
    guard !hasDuplicateSentences(trimmed) else { return false }
    guard !containsLowQualityPhrases(trimmed) else { return false }

    let normalizedGenerated = normalizeText(trimmed).lowercased()
    let normalizedSource = normalizeText(sourceText).lowercased()
    guard normalizedGenerated != normalizedSource else { return false }

    if let existing = candidate.synopsis_enhanced,
       !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       normalizeText(existing).lowercased() == normalizedGenerated {
        return false
    }

    let count = sentenceCount(in: trimmed)
    guard count >= config.minSentences else { return false }
    guard count <= config.maxSentences else { return false }
    return true
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

func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
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
        let reportsRoot = URL(fileURLWithPath: stringEnv("SYNOPSIS_REPORTS_DIR", default: "/Applications/Kuro/reports/synopsis-enrichment"), isDirectory: true)
        let client = RPCClient(baseURL: baseURL, serviceRoleKey: serviceRoleKey)

        try FileManager.default.createDirectory(at: reportsRoot, withIntermediateDirectories: true)

        let started = Date()
        var metrics = RunMetrics(
            started_at: isoNow(),
            finished_at: isoNow(),
            processed: 0,
            generated: 0,
            tone_polish_used: 0,
            fallback_used: 0,
            autodeduped_sentences: 0,
            rejected_quality: 0,
            insufficient_source: 0,
            failed: 0,
            avg_latency_ms: 0,
            backlog_due_before: 0,
            backlog_due_after: 0,
            backlog_remaining_estimate: 0
        )

        var latencySamples: [Int] = []
        var weakSourceEntries: [WeakSourceEntry] = []
        var generatedEntries: [GeneratedSynopsisEntry] = []

        for mediaType in mediaTypes {
            let backlogRows: [BacklogCountRow] = try await client.rpc(
                "get_synopsis_enrichment_backlog_count",
                payload: ["p_media_type": mediaType],
                as: [BacklogCountRow].self
            )
            metrics.backlog_due_before += backlogRows.first?.backlog_count ?? 0
        }

        for mediaType in mediaTypes {
            let candidates: [Candidate] = try await client.rpc(
                "get_synopsis_enrichment_candidates",
                payload: ["p_media_type": mediaType, "p_limit": batchSize],
                as: [Candidate].self
            )

            for candidate in candidates {
                metrics.processed += 1
                let sourceText = bestSourceText(for: candidate)
                if sourceText.count < quality.minSourceChars {
                    metrics.insufficient_source += 1
                    weakSourceEntries.append(
                        WeakSourceEntry(
                            mediaType: candidate.media_type,
                            mediaId: candidate.media_id,
                            title: candidate.title,
                            sourceChars: sourceText.count,
                            reason: "insufficient_source_text"
                        )
                    )
                    try? await client.rpcNoContent(
                        "mark_synopsis_enhanced_failed",
                        payload: [
                            "p_media_type": candidate.media_type,
                            "p_media_id": candidate.media_id,
                            "p_reason": "insufficient_source_text"
                        ]
                    )
                    continue
                }
                let startMs = Date()
                do {
                    let generatedRaw = await generateSynopsis(title: candidate.title, source: sourceText, config: quality)
                    var post = postProcessSynopsis(generatedRaw, config: quality)
                    var generated = post.text
                    let latency = Int(Date().timeIntervalSince(startMs) * 1000)
                    latencySamples.append(latency)

                    if !passesQualityGates(candidate: candidate, generated: generated, sourceText: sourceText, config: quality) {
                        let polishedRaw = await polishSynopsisTone(
                            title: candidate.title,
                            source: sourceText,
                            draft: generated,
                            config: quality
                        )
                        if normalizeText(polishedRaw).lowercased() != normalizeText(generated).lowercased() {
                            metrics.tone_polish_used += 1
                        }
                        post = postProcessSynopsis(polishedRaw, config: quality)
                        generated = post.text
                    }

                    if !passesQualityGates(candidate: candidate, generated: generated, sourceText: sourceText, config: quality) {
                        metrics.fallback_used += 1
                        let fallbackRaw = heuristicSynopsis(title: candidate.title, source: sourceText, config: quality)
                        post = postProcessSynopsis(fallbackRaw, config: quality)
                        generated = post.text
                    }

                    if !passesQualityGates(candidate: candidate, generated: generated, sourceText: sourceText, config: quality) {
                        metrics.rejected_quality += 1
                        try await client.rpcNoContent(
                            "mark_synopsis_enhanced_failed",
                            payload: [
                                "p_media_type": candidate.media_type,
                                "p_media_id": candidate.media_id,
                                "p_reason": "quality_gate_style_or_structure"
                            ]
                        )
                        continue
                    }
                    metrics.autodeduped_sentences += post.dedupedCount

                    try await client.rpcNoContent(
                        "upsert_synopsis_enhanced",
                        payload: [
                            "p_media_type": candidate.media_type,
                            "p_media_id": candidate.media_id,
                            "p_text": generated,
                            "p_meta": [
                                "source": "apple_fm_local",
                                "model": "system_language_model",
                                "version": "v1.1"
                            ]
                        ]
                    )
                    metrics.generated += 1
                    if generatedEntries.count < 20 {
                        generatedEntries.append(
                            GeneratedSynopsisEntry(
                                mediaType: candidate.media_type,
                                mediaId: candidate.media_id,
                                title: candidate.title,
                                synopsis: generated
                            )
                        )
                    }
                } catch {
                    metrics.failed += 1
                    try? await client.rpcNoContent(
                        "mark_synopsis_enhanced_failed",
                        payload: [
                            "p_media_type": candidate.media_type,
                            "p_media_id": candidate.media_id,
                            "p_reason": String(describing: error).prefix(180)
                        ]
                    )
                }
            }
        }

        for mediaType in mediaTypes {
            let backlogRows: [BacklogCountRow] = try await client.rpc(
                "get_synopsis_enrichment_backlog_count",
                payload: ["p_media_type": mediaType],
                as: [BacklogCountRow].self
            )
            metrics.backlog_due_after += backlogRows.first?.backlog_count ?? 0
        }
        metrics.backlog_remaining_estimate = metrics.backlog_due_after

        metrics.finished_at = isoNow()
        if !latencySamples.isEmpty {
            metrics.avg_latency_ms = latencySamples.reduce(0, +) / latencySamples.count
        }

        let statusData = try JSONEncoder.enrichmentEncoder.encode(metrics)
        let latestStatusURL = reportsRoot.appendingPathComponent("latest-status.json")
        try statusData.write(to: latestStatusURL, options: .atomic)

        let runName = ISO8601DateFormatter().string(from: started).replacingOccurrences(of: ":", with: "-")
        let runLogURL = reportsRoot.appendingPathComponent("run-\(runName).log")
        let summary = "processed=\(metrics.processed) generated=\(metrics.generated) tone_polish_used=\(metrics.tone_polish_used) fallback_used=\(metrics.fallback_used) autodeduped_sentences=\(metrics.autodeduped_sentences) rejected_quality=\(metrics.rejected_quality) insufficient_source=\(metrics.insufficient_source) failed=\(metrics.failed) avg_latency_ms=\(metrics.avg_latency_ms) backlog_due_before=\(metrics.backlog_due_before) backlog_due_after=\(metrics.backlog_due_after)"
        try summary.appending("\n").write(to: runLogURL, atomically: true, encoding: .utf8)

        if !weakSourceEntries.isEmpty {
            let md = buildWeakSourceMarkdown(
                generatedAt: metrics.finished_at,
                minSourceChars: quality.minSourceChars,
                entries: weakSourceEntries
            )
            let latestWeakURL = reportsRoot.appendingPathComponent("weak-sources-latest.md")
            try md.write(to: latestWeakURL, atomically: true, encoding: .utf8)
            let runWeakURL = reportsRoot.appendingPathComponent("weak-sources-\(runName).md")
            try md.write(to: runWeakURL, atomically: true, encoding: .utf8)
        }

        let generatedMd = buildGeneratedSynopsisMarkdown(
            generatedAt: metrics.finished_at,
            entries: generatedEntries
        )
        let latestGeneratedURL = reportsRoot.appendingPathComponent("generated-samples-latest.md")
        try generatedMd.write(to: latestGeneratedURL, atomically: true, encoding: .utf8)
        let runGeneratedURL = reportsRoot.appendingPathComponent("generated-samples-\(runName).md")
        try generatedMd.write(to: runGeneratedURL, atomically: true, encoding: .utf8)

        if let statusText = String(data: statusData, encoding: .utf8) {
            print(statusText)
        }
    }
}

func buildWeakSourceMarkdown(
    generatedAt: String,
    minSourceChars: Int,
    entries: [WeakSourceEntry]
) -> String {
    var lines: [String] = []
    lines.append("# Weak Synopsis Sources")
    lines.append("")
    lines.append("- Generated at: \(generatedAt)")
    lines.append("- Rule: source text must be at least \(minSourceChars) characters")
    lines.append("- Count: \(entries.count)")
    lines.append("")
    lines.append("| Media | ID | Title | Source chars | Reason |")
    lines.append("| --- | ---: | --- | ---: | --- |")
    for entry in entries.sorted(by: {
        if $0.mediaType != $1.mediaType { return $0.mediaType < $1.mediaType }
        return $0.mediaId < $1.mediaId
    }) {
        let safeTitle = entry.title.replacingOccurrences(of: "|", with: "\\|")
        lines.append("| \(entry.mediaType) | \(entry.mediaId) | \(safeTitle) | \(entry.sourceChars) | \(entry.reason) |")
    }
    lines.append("")
    lines.append("## Manual Research Notes")
    lines.append("- Fill this section with trusted source links and rewritten synopsis notes.")
    lines.append("- Re-run the worker after source records are improved.")
    lines.append("")
    return lines.joined(separator: "\n")
}

func buildGeneratedSynopsisMarkdown(
    generatedAt: String,
    entries: [GeneratedSynopsisEntry]
) -> String {
    var lines: [String] = []
    lines.append("# Generated Synopsis Samples")
    lines.append("")
    lines.append("- Generated at: \(generatedAt)")
    lines.append("- Count: \(entries.count)")
    lines.append("")

    if entries.isEmpty {
        lines.append("No generated synopsis samples in this run.")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    for entry in entries {
        let safeTitle = entry.title.replacingOccurrences(of: "|", with: "\\|")
        let synopsis = normalizeText(entry.synopsis).replacingOccurrences(of: "|", with: "\\|")
        lines.append("## \(entry.mediaType) \(entry.mediaId) - \(safeTitle)")
        lines.append("")
        lines.append(synopsis)
        lines.append("")
    }

    return lines.joined(separator: "\n")
}
