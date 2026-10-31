import Foundation

struct Candidate: Decodable {
    let media_type: String
    let media_id: Int
    let title: String
    let source_description: String
    let source_description_normalized: String?
    let synopsis_enhanced: String?
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
