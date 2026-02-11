import Foundation
import SwiftUI
import CryptoKit

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Result Types (always available, not behind #if canImport)

struct DisambiguationCandidate {
    let index: Int
    let title: String
    let year: Int?
    let format: String?
    let score: Double
    let variantType: String
}

struct DisambiguationResult {
    let selectedIndex: Int
    let reasoning: String
}

struct ModeClassificationResult {
    let modeId: String
    let reason: String
}

struct CollectionSearchIntent {
    let genre: String?
    let status: String?
    let yearFrom: Int?
    let yearTo: Int?
    let keywords: [String]
}

struct FMIntentAssist {
    let reasoning: String
    let selectedIntent: String
    let confidence: Double
}

struct FMSlotAssist {
    let reasoning: String
    let extractedStatus: String?
    let extractedProgress: Int?
    let extractedUnit: String?
}

struct FMDisambiguationAssist {
    let reasoning: String
    let rankedIndices: [Int]
    let confidence: Double
}

// MARK: - Error Types

enum AppleFMError: Error {
    case modelNotAvailable
    case timeout
    case generationFailed(Error)
    case invalidOutput
}

// MARK: - Protocol for Testability

@MainActor
protocol FMProvider {
    var isAvailable: Bool { get }
    func classifyMode(userText: String, availableModes: [(id: String, title: String, synonyms: [String])]) async -> ModeClassificationResult?
    func disambiguate(candidates: [DisambiguationCandidate], userText: String, rawTitle: String) async -> DisambiguationResult?
    func condenseSynopsis(description: String, title: String, genres: [String]) async -> String?
    func parseSearchIntent(query: String) async -> CollectionSearchIntent?
    func assistIntent(text: String, locale: String) async -> FMIntentAssist?
    func assistSlots(text: String, locale: String, partialSlots: [String: Any]) async -> FMSlotAssist?
    func assistDisambiguate(text: String, candidates: [(title: String, year: Int?)]) async -> FMDisambiguationAssist?
}

// MARK: - @Generable Structs (inside compile-time guard)

#if canImport(FoundationModels)

@available(iOS 26, *)
@Generable
struct FMDisambiguationOutput {
    @Guide(description: "Brief reason for your selection, considering year mentions, format, and context clues")
    var reasoning: String
    @Guide(description: "0-based index of the best matching candidate from the list")
    var selectedIndex: Int
}

@available(iOS 26, *)
@Generable
struct FMModeOutput {
    @Guide(description: "Brief reason for classification")
    var reason: String
    @Guide(description: "The mode_id that best matches the user's request")
    var modeId: String
}

@available(iOS 26, *)
@Generable
struct FMSynopsisOutput {
    @Guide(description: "A spoiler-free 2-sentence hook focusing on premise, tone, and genre. No character deaths, betrayals, or late-series revelations.")
    var hook: String
}

@available(iOS 26, *)
@Generable
struct FMSearchIntentOutput {
    @Guide(description: "Genre filter extracted from query, or empty string if none")
    var genre: String
    @Guide(description: "Status filter: WATCHING, COMPLETED, PLANNING, PAUSED, DROPPED, or empty string")
    var status: String
    @Guide(description: "Start year extracted from query, or 0 if none")
    var yearFrom: Int
    @Guide(description: "End year extracted from query, or 0 if none")
    var yearTo: Int
    @Guide(description: "Keywords for title matching")
    var keywords: [String]
}

@available(iOS 26, *)
@Generable
struct FMIntentClassificationOutput {
    @Guide(description: "Think step by step about what the user wants to do")
    var reasoning: String
    @Guide(description: "The detected intent: import, recommend_vibe, recommend_seed, library_query, club_action, or unknown")
    var selectedIntent: String
    @Guide(description: "Confidence 0.0-1.0")
    var confidence: Double
}

@available(iOS 26, *)
@Generable
struct FMSlotExtractionOutput {
    @Guide(description: "Think step by step about what status and progress info is present")
    var reasoning: String
    @Guide(description: "Extracted status: COMPLETED, CURRENT, PLANNING, PAUSED, DROPPED, or empty string if unclear")
    var extractedStatus: String
    @Guide(description: "Extracted progress number, or 0 if none found")
    var extractedProgress: Int
    @Guide(description: "Progress unit: episode, season, chapter, volume, or empty string if unclear")
    var extractedUnit: String
}

@available(iOS 26, *)
@Generable
struct FMDisambiguationRankOutput {
    @Guide(description: "Think step by step about which candidates best match the user's query")
    var reasoning: String
    @Guide(description: "0-based indices of candidates ranked from most to least relevant")
    var rankedIndices: [Int]
    @Guide(description: "Confidence 0.0-1.0 in the ranking")
    var confidence: Double
}

#endif

// MARK: - Input Sanitization

/// Strips prompt-injection patterns, markdown fences, HTML tags, and truncates
/// user text before passing it to FM prompts. Mirrors the server-side sanitizeForLLM().
private func sanitizeForLLM(_ text: String, maxLength: Int = 2000) -> String {
    var s = text

    // Strip markdown code fences
    s = s.replacingOccurrences(of: "```", with: "")

    // Strip HTML tags
    let htmlTagPattern = try? NSRegularExpression(pattern: "<[^>]+>", options: [])
    s = htmlTagPattern?.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "") ?? s

    // Strip common injection patterns (case-insensitive)
    let injectionPatterns = [
        "ignore previous instructions",
        "ignore all instructions",
        "you are now",
        "system prompt",
        "forget everything",
        "new instructions",
        "override",
        "jailbreak",
    ]
    for pattern in injectionPatterns {
        if let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: pattern), options: .caseInsensitive) {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
    }

    // Collapse excessive whitespace
    s = s.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    // Truncate
    if s.count > maxLength {
        s = String(s.prefix(maxLength))
    }

    return s
}

// MARK: - Apple FM Service

@MainActor
@Observable
final class AppleFMService: FMProvider {

    // Synopsis cache (mediaId -> condensed text)
    private var synopsisCache: [Int: String] = [:]

    // Assist cache (keyed by normalized input hash)
    private struct AssistCacheEntry {
        let result: Any
        let timestamp: Date
    }
    private var assistCache: [String: AssistCacheEntry] = [:]
    private let assistCacheMaxEntries = 100
    private let assistCacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Availability

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    // MARK: - Mode Classification

    func classifyMode(
        userText: String,
        availableModes: [(id: String, title: String, synonyms: [String])]
    ) async -> ModeClassificationResult? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), SystemLanguageModel.default.isAvailable else { return nil }

        let sanitized = sanitizeForLLM(userText)
        let modeList = availableModes.map { mode in
            let syns = mode.synonyms.isEmpty ? "" : " (also: \(mode.synonyms.joined(separator: ", ")))"
            return "- \(mode.id): \(mode.title)\(syns)"
        }.joined(separator: "\n")

        let prompt = """
        You classify anime/manga preference queries into recommendation categories. \
        Pick exactly one mode_id from the allowed list. \
        If no mode clearly matches, pick "premium_picks".

        Query: "\(sanitized)"

        Available modes:
        \(modeList)
        """

        do {
            let output: FMModeOutput = try await withFMTimeout(seconds: 5) {
                let session = LanguageModelSession()
                return try await session.respond(to: prompt, generating: FMModeOutput.self).content
            }

            // Validate: returned modeId must exist in the available modes list
            let validIds = Set(availableModes.map(\.id))
            guard validIds.contains(output.modeId) else { return nil }

            return ModeClassificationResult(modeId: output.modeId, reason: output.reason)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Disambiguation

    func disambiguate(
        candidates: [DisambiguationCandidate],
        userText: String,
        rawTitle: String
    ) async -> DisambiguationResult? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), SystemLanguageModel.default.isAvailable else { return nil }
        guard candidates.count >= 2 else { return nil }

        let sanitizedText = sanitizeForLLM(userText)
        let sanitizedTitle = sanitizeForLLM(rawTitle)
        let candidateList = candidates.enumerated().map { i, c in
            var parts = ["\(i): \"\(c.title)\""]
            if let y = c.year { parts.append("year=\(y)") }
            if let f = c.format { parts.append("format=\(f)") }
            parts.append("type=\(c.variantType)")
            parts.append("score=\(String(format: "%.1f", c.score))")
            return parts.joined(separator: ", ")
        }.joined(separator: "\n")

        let prompt = """
        You disambiguate anime/manga title matches. The user searched for "\(sanitizedTitle)" \
        in the context: "\(sanitizedText)". Pick the best matching candidate by index.

        Candidates:
        \(candidateList)
        """

        do {
            let output: FMDisambiguationOutput = try await withFMTimeout(seconds: 8) {
                let session = LanguageModelSession()
                return try await session.respond(to: prompt, generating: FMDisambiguationOutput.self).content
            }

            // Bounds-check selectedIndex
            guard output.selectedIndex >= 0, output.selectedIndex < candidates.count else {
                return nil
            }

            return DisambiguationResult(
                selectedIndex: output.selectedIndex,
                reasoning: output.reasoning
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Synopsis Condenser

    func condenseSynopsis(description: String, title: String, genres: [String]) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), SystemLanguageModel.default.isAvailable else { return nil }
        guard !description.isEmpty else { return nil }

        // Check cache first (keyed on hash of description since we don't have mediaId here)
        let cacheKey = description.hashValue
        if let cached = synopsisCache[cacheKey] { return cached }

        let sanitizedTitle = sanitizeForLLM(title, maxLength: 500)
        let sanitizedDesc = sanitizeForLLM(description)
        let genreStr = genres.isEmpty ? "Unknown" : genres.joined(separator: ", ")
        let prompt = """
        You condense anime/manga descriptions into 2-sentence hooks. \
        Focus on premise and tone. Never include spoilers, character deaths, or late-series plot points. \
        Match the source language.

        Title: \(sanitizedTitle)
        Genres: \(genreStr)
        Description: \(sanitizedDesc)
        """

        do {
            let output: FMSynopsisOutput = try await withFMTimeout(seconds: 10) {
                let session = LanguageModelSession()
                return try await session.respond(to: prompt, generating: FMSynopsisOutput.self).content
            }

            let hook = output.hook.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hook.isEmpty else { return nil }

            synopsisCache[cacheKey] = hook
            return hook
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Condense with an explicit mediaId for stable caching.
    func condenseSynopsis(mediaId: Int, description: String, title: String, genres: [String]) async -> String? {
        if let cached = synopsisCache[mediaId] { return cached }
        guard let result = await condenseSynopsis(description: description, title: title, genres: genres) else {
            return nil
        }
        synopsisCache[mediaId] = result
        return result
    }

    // MARK: - Collection Search Intent Parsing

    func parseSearchIntent(query: String) async -> CollectionSearchIntent? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), SystemLanguageModel.default.isAvailable else { return nil }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let sanitized = sanitizeForLLM(query)
        let prompt = """
        Extract search filters from this anime/manga collection query. \
        Only extract what is explicitly stated. Leave fields empty or zero if not mentioned. \
        Valid statuses: WATCHING, COMPLETED, PLANNING, PAUSED, DROPPED.

        Query: "\(sanitized)"
        """

        do {
            let output: FMSearchIntentOutput = try await withFMTimeout(seconds: 5) {
                let session = LanguageModelSession()
                return try await session.respond(to: prompt, generating: FMSearchIntentOutput.self).content
            }

            return CollectionSearchIntent(
                genre: output.genre.isEmpty ? nil : output.genre,
                status: output.status.isEmpty ? nil : output.status,
                yearFrom: output.yearFrom > 0 ? output.yearFrom : nil,
                yearTo: output.yearTo > 0 ? output.yearTo : nil,
                keywords: output.keywords.filter { !$0.isEmpty }
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Intent Assist

    func assistIntent(text: String, locale: String) async -> FMIntentAssist? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), SystemLanguageModel.default.isAvailable else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let cacheKey = assistCacheKey(text: text, locale: locale, extra: "intent")
        if let cached: FMIntentAssist = assistCacheLookup(key: cacheKey) { return cached }

        let sanitized = sanitizeForLLM(text)
        let prompt = """
        You classify user messages about anime/manga into intents. \
        The user's locale is "\(locale)". Respond based on what the user wants to do.

        Allowed intents: import, recommend_vibe, recommend_seed, library_query, club_action, unknown

        - import: user wants to add/update/track a specific title in their list (e.g. status, progress, rating)
        - recommend_vibe: user wants recommendations by mood/vibe (e.g. "something dark", "etwas Lustiges")
        - recommend_seed: user wants recommendations similar to a specific title (e.g. "like Attack on Titan")
        - library_query: user wants to search/filter their existing collection
        - club_action: user wants to do something with a club (create, invite, poll, share)
        - unknown: none of the above

        Message: "\(sanitized)"
        """

        do {
            let output: FMIntentClassificationOutput = try await withFMTimeout(seconds: 3) {
                let session = LanguageModelSession()
                return try await session.respond(to: prompt, generating: FMIntentClassificationOutput.self).content
            }

            let validIntents: Set<String> = ["import", "recommend_vibe", "recommend_seed", "library_query", "club_action", "unknown"]
            guard validIntents.contains(output.selectedIntent) else { return nil }

            let confidence = max(0.0, min(1.0, output.confidence))
            let result = FMIntentAssist(
                reasoning: output.reasoning,
                selectedIntent: output.selectedIntent,
                confidence: confidence
            )
            assistCacheStore(key: cacheKey, result: result)
            return result
        } catch {
            #if DEBUG
            print("[AppleFMService] assistIntent error: \(error)")
            #endif
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Slot Assist

    func assistSlots(text: String, locale: String, partialSlots: [String: Any]) async -> FMSlotAssist? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), SystemLanguageModel.default.isAvailable else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let slotContext = partialSlots.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")
        let cacheKey = assistCacheKey(text: text, locale: locale, extra: "slots:\(slotContext)")
        if let cached: FMSlotAssist = assistCacheLookup(key: cacheKey) { return cached }

        let sanitized = sanitizeForLLM(text)
        let prompt = """
        You extract status and progress information from anime/manga user messages. \
        The user's locale is "\(locale)".

        Already parsed slots: \(slotContext.isEmpty ? "none" : slotContext)

        Extract any missing information:
        - Status: COMPLETED, CURRENT, PLANNING, PAUSED, or DROPPED
        - Progress number: the episode/chapter/volume number mentioned
        - Progress unit: episode, season, chapter, or volume

        Only extract what is clearly stated. Leave empty/zero if ambiguous.

        Message: "\(sanitized)"
        """

        do {
            let output: FMSlotExtractionOutput = try await withFMTimeout(seconds: 3) {
                let session = LanguageModelSession()
                return try await session.respond(to: prompt, generating: FMSlotExtractionOutput.self).content
            }

            // Validate status against canonical set
            let validStatuses: Set<String> = ["COMPLETED", "CURRENT", "PLANNING", "PAUSED", "DROPPED"]
            let status = output.extractedStatus.isEmpty ? nil : output.extractedStatus.uppercased()
            let validatedStatus = status.flatMap { validStatuses.contains($0) ? $0 : nil }

            // Validate unit against known units
            let validUnits: Set<String> = ["episode", "season", "chapter", "volume"]
            let unit = output.extractedUnit.isEmpty ? nil : output.extractedUnit.lowercased()
            let validatedUnit = unit.flatMap { validUnits.contains($0) ? $0 : nil }

            let result = FMSlotAssist(
                reasoning: output.reasoning,
                extractedStatus: validatedStatus,
                extractedProgress: output.extractedProgress > 0 ? output.extractedProgress : nil,
                extractedUnit: validatedUnit
            )
            assistCacheStore(key: cacheKey, result: result)
            return result
        } catch {
            #if DEBUG
            print("[AppleFMService] assistSlots error: \(error)")
            #endif
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Disambiguation Assist

    func assistDisambiguate(text: String, candidates: [(title: String, year: Int?)]) async -> FMDisambiguationAssist? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), SystemLanguageModel.default.isAvailable else { return nil }
        guard candidates.count >= 2 else { return nil }

        let candidateHash = candidates.map { "\($0.title)|\($0.year ?? 0)" }.joined(separator: ";")
        let cacheKey = assistCacheKey(text: text, locale: "", extra: "disambig:\(candidateHash)")
        if let cached: FMDisambiguationAssist = assistCacheLookup(key: cacheKey) { return cached }

        let sanitized = sanitizeForLLM(text)
        let candidateList = candidates.enumerated().map { i, c in
            var desc = "\(i): \"\(c.title)\""
            if let y = c.year { desc += " (\(y))" }
            return desc
        }.joined(separator: "\n")

        let prompt = """
        You rank anime/manga title candidates by relevance to the user's query. \
        Rank all candidates from most to least relevant.

        Query: "\(sanitized)"

        Candidates:
        \(candidateList)
        """

        do {
            let output: FMDisambiguationRankOutput = try await withFMTimeout(seconds: 3) {
                let session = LanguageModelSession()
                return try await session.respond(to: prompt, generating: FMDisambiguationRankOutput.self).content
            }

            // Validate: all indices must be in bounds and unique
            let validRange = 0..<candidates.count
            let filtered = output.rankedIndices.filter { validRange.contains($0) }
            let unique = filtered.reduce(into: [Int]()) { result, idx in
                if !result.contains(idx) { result.append(idx) }
            }
            guard !unique.isEmpty else { return nil }

            let confidence = max(0.0, min(1.0, output.confidence))
            let result = FMDisambiguationAssist(
                reasoning: output.reasoning,
                rankedIndices: unique,
                confidence: confidence
            )
            assistCacheStore(key: cacheKey, result: result)
            return result
        } catch {
            #if DEBUG
            print("[AppleFMService] assistDisambiguate error: \(error)")
            #endif
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Assist Cache Helpers

    private func assistCacheKey(text: String, locale: String, extra: String) -> String {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = "\(extra)|\(normalized)|\(locale)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func assistCacheLookup<T>(key: String) -> T? {
        guard let entry = assistCache[key] else { return nil }
        guard Date().timeIntervalSince(entry.timestamp) < assistCacheTTL else {
            assistCache.removeValue(forKey: key)
            return nil
        }
        return entry.result as? T
    }

    private func assistCacheStore(key: String, result: Any) {
        // Evict oldest entries if at capacity
        if assistCache.count >= assistCacheMaxEntries {
            let sortedKeys = assistCache.sorted { $0.value.timestamp < $1.value.timestamp }
            let toRemove = sortedKeys.prefix(assistCache.count - assistCacheMaxEntries + 1)
            for (k, _) in toRemove {
                assistCache.removeValue(forKey: k)
            }
        }
        assistCache[key] = AssistCacheEntry(result: result, timestamp: Date())
    }

    // MARK: - Cache Management

    func clearSynopsisCache() {
        synopsisCache.removeAll()
    }

    func clearAssistCache() {
        assistCache.removeAll()
    }

    var synopsisCacheCount: Int {
        synopsisCache.count
    }

    var assistCacheCount: Int {
        assistCache.count
    }
}

// MARK: - Timeout Helper

#if canImport(FoundationModels)

@available(iOS 26, *)
private func withFMTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw AppleFMError.timeout
        }
        guard let result = try await group.next() else {
            throw AppleFMError.timeout
        }
        group.cancelAll()
        return result
    }
}

#endif

// MARK: - Stub for Non-FM Devices

/// A no-op provider for devices/OS versions that don't support Apple Foundation Models.
@MainActor
final class StubFMProvider: FMProvider {
    var isAvailable: Bool { false }

    func classifyMode(userText: String, availableModes: [(id: String, title: String, synonyms: [String])]) async -> ModeClassificationResult? {
        nil
    }

    func disambiguate(candidates: [DisambiguationCandidate], userText: String, rawTitle: String) async -> DisambiguationResult? {
        nil
    }

    func condenseSynopsis(description: String, title: String, genres: [String]) async -> String? {
        nil
    }

    func parseSearchIntent(query: String) async -> CollectionSearchIntent? {
        nil
    }

    func assistIntent(text: String, locale: String) async -> FMIntentAssist? {
        nil
    }

    func assistSlots(text: String, locale: String, partialSlots: [String: Any]) async -> FMSlotAssist? {
        nil
    }

    func assistDisambiguate(text: String, candidates: [(title: String, year: Int?)]) async -> FMDisambiguationAssist? {
        nil
    }
}
