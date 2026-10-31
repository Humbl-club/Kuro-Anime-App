import Foundation

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

struct CatalogSafetyModelResult {
    let label: String
    let confidence: Double
    let rationale: String
    let suggestedTerms: [String]
    let available: Bool
}

func normalizeText(_ text: String) -> String {
    text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
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

func decideSafety(
    candidate: SafetyCandidate,
    terms: [SafetyTerm],
    minBlockedConfidence: Double,
    minSafeConfidence: Double,
    safeFallbackMaxRuleScore: Int,
    classify: (SafetyCandidate) async -> CatalogSafetyModelResult
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

    let model = await classify(candidate)
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
