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
        let placeholder: Character = "\u{0000}"

        // Protect hyphens between letters
        for i in 1 ..< (chars.count > 0 ? chars.count - 1 : 0) {
            if chars[i] == "-",
               chars[i - 1].isLetter,
               chars[i + 1].isLetter {
                chars[i] = placeholder
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
}
