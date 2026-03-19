// MARK: - TextNormalization.swift
// Shared text normalization utilities for EN/DE bilingual concierge.
// This MUST produce IDENTICAL output to supabase/functions/_shared/normalization.ts.

import Foundation

enum TextNormalization {

    // MARK: - Umlaut Folding

    /// Fold German umlauts and Eszett to ASCII equivalents.
    /// Handles both lowercase and uppercase forms.
    static func umlautFold(_ text: String) -> String {
        text
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "Ä", with: "Ae")
            .replacingOccurrences(of: "Ö", with: "Oe")
            .replacingOccurrences(of: "Ü", with: "Ue")
    }

    // MARK: - Text Normalization

    /// Normalize text for comparison: lowercase, collapse whitespace, strip
    /// punctuation but preserve hyphens in compound words (e.g. "Lieblings-Anime").
    static func normalizeText(_ text: String) -> String {
        var s = text.lowercased()

        // Replace underscores and slashes/backslashes with space
        s = s.replacingOccurrences(of: "_", with: " ")
        s = s.replacingOccurrences(of: "/", with: " ")
        s = s.replacingOccurrences(of: "\\", with: " ")

        // Protect hyphens between letter characters, then strip punctuation.
        // We iterate through characters to match the TS regex behavior exactly.
        var chars = Array(s)
        let placeholder: Swift.Character = "\u{0000}"

        // Protect hyphens between letters.
        // Guard the range explicitly to avoid creating an invalid `1..<0` range on empty/short input.
        if chars.count >= 3 {
            for i in 1 ..< (chars.count - 1) {
                if chars[i] == "-",
                   chars[i - 1].isLetter,
                   chars[i + 1].isLetter {
                    chars[i] = placeholder
                }
            }
        }

        // Strip non-letter, non-number, non-space, non-placeholder
        chars = chars.map { c in
            if c == placeholder { return c }
            if c.isLetter || c.isNumber || c.isWhitespace { return c }
            return " "
        }

        // Restore protected hyphens
        chars = chars.map { $0 == placeholder ? "-" : $0 }

        s = String(chars)

        // Collapse whitespace
        s = s.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return s
    }

    // MARK: - German Inflection Normalization

    /// Common DE suffixes to strip, ordered longest-first.
    private static let deSuffixes = [
        "ungen", "keit", "heit", "ung", "en", "er", "es", "em", "e",
    ]

    /// Strip common German inflection suffixes to approximate the lemma.
    /// Only strips if the remaining stem is longer than 4 characters.
    /// For compound words (hyphenated), each part is normalized independently.
    static func germanInflectionNormalize(_ word: String) -> String {
        // Handle compound words: normalize each part independently
        if word.contains("-") {
            return word.split(separator: "-", omittingEmptySubsequences: false)
                .map { germanInflectionNormalize(String($0)) }
                .joined(separator: "-")
        }
        guard word.count > 4 else { return word }
        for suffix in deSuffixes {
            if word.hasSuffix(suffix), (word.count - suffix.count) > 4 {
                return String(word.dropLast(suffix.count))
            }
        }
        return word
    }

    // MARK: - Stopword Filtering

    private static let stopwordsDE: Set<String> = [
        "der", "die", "das", "den", "dem", "des",
        "ein", "eine", "einen", "einem", "eines", "einer",
        "und", "oder", "ist", "sind",
        "war", "hat", "haben", "für", "fuer", "mit", "auf", "von", "zu",
        "aus", "nach", "bei", "durch", "über", "ueber", "in", "an", "um",
        "nicht", "kein", "keine",
    ]

    private static let stopwordsEN: Set<String> = [
        "the", "a", "an", "is", "are", "was", "has", "have", "for", "with",
        "on", "of", "to", "from", "at", "by", "through", "over", "in",
        "not", "no",
    ]

    /// Remove locale-specific stopwords from a token array.
    static func filterStopwords(_ tokens: [String], locale: String) -> [String] {
        let lang = String(locale.lowercased().prefix(2))
        let stops: Set<String>
        switch lang {
        case "de": stops = stopwordsDE
        case "en": stops = stopwordsEN
        default: return tokens
        }
        return tokens.filter { !stops.contains($0) }
    }

    // MARK: - Full Search Normalization Pipeline

    /// Full normalization pipeline for search/matching:
    ///   normalizeText -> umlautFold -> split -> filterStopwords
    ///   -> germanInflectionNormalize (if DE) -> join
    ///
    /// Produces a stable, comparable string for both client and server.
    static func normalizeForSearch(_ text: String, locale: String) -> String {
        let normalized = normalizeText(text)
        let folded = umlautFold(normalized)
        let tokens = folded.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let filtered = filterStopwords(tokens, locale: locale)
        let lang = String(locale.lowercased().prefix(2))
        let stemmed: [String]
        if lang == "de" {
            stemmed = filtered.map { germanInflectionNormalize($0) }
        } else {
            stemmed = filtered
        }
        return stemmed.joined(separator: " ")
    }

    // MARK: - Media Description Sanitization

    /// Clean AniList-style synopsis HTML into readable plain text for UI display.
    static func sanitizeMediaDescription(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        text = replacing(pattern: "(?i)<br\\s*/?>", in: text, with: "\n\n")
        text = replacing(pattern: "(?i)</p\\s*>", in: text, with: "\n\n")
        text = replacing(pattern: "(?i)<p\\b[^>]*>", in: text, with: "")
        text = replacing(pattern: "(?i)<[^>]+>", in: text, with: "")

        let entities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&#x27;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&rsquo;": "'",
            "&ldquo;": "\"",
            "&rdquo;": "\"",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        text = replacing(pattern: "[ \\t]+\\n", in: text, with: "\n")
        text = replacing(pattern: "\\n{3,}", in: text, with: "\n\n")
        text = replacing(pattern: "[ \\t]{2,}", in: text, with: " ")

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - Import Intent Detection

    /// Lightweight keyword-based check for whether user text looks like a list import
    /// (as opposed to a recommendation/vibe request). Used as the primary intent router
    /// on non-FM devices and as a fallback when FM is unavailable or low-confidence.
    ///
    /// The server-side parser (`concierge-parse/index.ts`) is the authoritative classifier;
    /// this is a fast client-side pre-router to avoid unnecessary network calls.
    static func looksLikeImport(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = t.lowercased()

        if t.contains("\n") { return true }

        // Explicit import language (EN + DE)
        if l.contains("watching") || l.contains("reading") || l.contains("completed") || l.contains("finished") || l.contains("dropped") { return true }
        if l.contains("watched") || l.contains("paused") || l.contains("saw ") || l.contains("i've seen") || l.contains("i have seen") { return true }
        if l.contains("i'm watching") || l.contains("im watching") || l.contains("i'm reading") || l.contains("im reading") { return true }
        if l.contains("caught up") || l.contains("up to date") { return true }
        if l.contains("halfway") || l.contains("half way") || l.contains("midway") || l.contains("partway") { return true }
        if l.contains("ich habe") || l.contains("ich schaue") || l.contains("ich gucke") || l.contains("ich sehe") || l.contains("ich lese") { return true }
        if l.contains("geschaut") || l.contains("gesehen") || l.contains("gelesen") || l.contains("zur hälfte") || l.contains("zur haelfte") { return true }
        if l.contains("staffel") || l.contains("folge") || l.contains("kapitel") || l.contains("band") { return true }

        // German vibe markers — these are NOT imports
        let germanVibeMarkers = ["etwas", "empfiehl", "empfehlung", "zeig mir", "ich möchte", "ich will", "ich suche"]
        if germanVibeMarkers.contains(where: { l.contains($0) }) && !l.contains("staffel") && !l.contains("folge") {
            return false
        }

        // Progress patterns
        if l.contains(" ep ") || l.contains("episode") || l.contains("chapter") || l.contains(" vol") { return true }
        if l.range(of: #"s\d{1,2}\s*e\d{1,4}"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"\b\d{1,2}\s*x\s*\d{1,4}\b"#, options: .regularExpression) != nil { return true }

        // Comma-separated lists
        if t.contains(",") {
            let parts = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count >= 2 {
                let titleLikeCount = parts.filter { segmentLooksTitleLike($0) }.count
                if titleLikeCount >= 2 { return true }
            }
        }

        if t.count <= 28 { return false }
        return false
    }

    /// Heuristic: does a comma-separated segment look like an anime/manga title
    /// (vs. a vibe descriptor like "something funny")?
    static func segmentLooksTitleLike(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return false }
        let l = t.lowercased()

        let vibeMarkers = ["something", "funny", "sad", "cozy", "vibe", "recommend", "suggest", "like", "but", "not", "please", "anime", "manga"]
        if vibeMarkers.contains(where: { l.contains($0) }) && t.split(separator: " ").count <= 6 {
            return false
        }

        if t.contains("(") || t.contains(")") { return true }
        if t.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"\b(ep|episode|ch|chapter|vol|volume|s\d+e\d+|\d+x\d+)\b"#, options: .regularExpression) != nil { return true }

        let words = t.split(separator: " ")
        if words.count >= 2 && t.range(of: #"[A-Z]"#, options: .regularExpression) != nil {
            return true
        }

        if words.count >= 3 { return true }

        return false
    }

    private static func replacing(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
