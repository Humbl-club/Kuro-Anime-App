import Foundation
import SwiftUI

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

#endif

// MARK: - Apple FM Service

@MainActor
@Observable
final class AppleFMService: FMProvider {

    // Synopsis cache (mediaId -> condensed text)
    private var synopsisCache: [Int: String] = [:]

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

        let modeList = availableModes.map { mode in
            let syns = mode.synonyms.isEmpty ? "" : " (also: \(mode.synonyms.joined(separator: ", ")))"
            return "- \(mode.id): \(mode.title)\(syns)"
        }.joined(separator: "\n")

        let prompt = """
        You classify anime/manga preference queries into recommendation categories. \
        Pick exactly one mode_id from the allowed list. \
        If no mode clearly matches, pick "premium_picks".

        Query: "\(userText)"

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

        let candidateList = candidates.enumerated().map { i, c in
            var parts = ["\(i): \"\(c.title)\""]
            if let y = c.year { parts.append("year=\(y)") }
            if let f = c.format { parts.append("format=\(f)") }
            parts.append("type=\(c.variantType)")
            parts.append("score=\(String(format: "%.1f", c.score))")
            return parts.joined(separator: ", ")
        }.joined(separator: "\n")

        let prompt = """
        You disambiguate anime/manga title matches. The user searched for "\(rawTitle)" \
        in the context: "\(userText)". Pick the best matching candidate by index.

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

        let genreStr = genres.isEmpty ? "Unknown" : genres.joined(separator: ", ")
        let prompt = """
        You condense anime/manga descriptions into 2-sentence hooks. \
        Focus on premise and tone. Never include spoilers, character deaths, or late-series plot points. \
        Match the source language.

        Title: \(title)
        Genres: \(genreStr)
        Description: \(description)
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

        let prompt = """
        Extract search filters from this anime/manga collection query. \
        Only extract what is explicitly stated. Leave fields empty or zero if not mentioned. \
        Valid statuses: WATCHING, COMPLETED, PLANNING, PAUSED, DROPPED.

        Query: "\(query)"
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

    // MARK: - Cache Management

    func clearSynopsisCache() {
        synopsisCache.removeAll()
    }

    var synopsisCacheCount: Int {
        synopsisCache.count
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
}
