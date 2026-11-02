import Foundation

// MARK: - Concierge routing rules (client side)
// The Concierge's client-side routing decisions, moved verbatim out of `ConciergeView` and
// `ConciergeInputField` (E6). Pure: text, on-device intent results and parse items in, decisions out;
// no SwiftUI, no SDK, no I/O, no state. The conversation itself stays session-local in the view.
//
// These are fast pre-routing heuristics only. They are separate from the `concierge-parse` edge
// parser (the authoritative import parser) and from `concierge-recommend` (server AI narrates only;
// it never routes or classifies). They decide which edge call a message makes, or that none is made.
//
// - Low-signal gate (`shouldAskClarifyingQuestion`): runs BEFORE the on-device intent classification
//   (by design: garbage never burns FM inference); a low-signal message gets the clarify card.
// - On-device intent (`onDeviceFlow`): trusted only at confidence >= `fmIntentMinimumConfidence`;
//   otherwise (or without a result) the keyword router (`keywordFlow`) decides.
// - Clarify answers (`clarificationRoute`): only intent_unclear + recommend_seed leaves the import
//   path; every other answer re-parses the source text with the clarification.
// - Parser clarification (`parserClarification`): the first parsed line's ambiguity, only while the
//   clarify card is enabled (clarify_v2).
// - Input field (`ConciergeIntentDetector`, `PrototypeConciergeIntent`): the live intent chip and the
//   paste auto-send. A third heuristic next to `TextNormalization.looksLikeImport` (routing) and the
//   low-signal gate; its `segmentLooksTitleLike` intentionally differs from TextNormalization's.

/// The flow a Concierge message is routed to.
enum ConciergeFlow: Equatable, Sendable {
    /// `concierge-parse`, then the import review (or auto-apply).
    case importList
    /// `concierge-recommend`, rendered as editorial rails.
    case recommendation
    /// "What would you like to do?" with the clarify actions; no network call.
    case clarify
}

/// What an answer on a parser clarify card does.
enum ConciergeClarificationRoute: Equatable, Sendable {
    /// The source text goes to the recommendation flow (intent_unclear answered with recommend_seed).
    case recommendation
    /// The source text is parsed again with the answer as its clarification (`[kind: value]`).
    case importReparse
}

enum ConciergeRouting {

    // MARK: Low-signal gate

    /// Known short anime abbreviations treated as a seed instead of asking (compared uppercased).
    /// Keep this set small and high-signal; the server still handles the rich parsing.
    static let knownAbbreviations: Set<String> = [
        "AOT", "HXH", "NGE", "EVA", "DB", "DBZ", "DBS", "SAO",
        "TPN", "BNHA", "OP"
    ]

    /// A single token of at most this many characters is low-signal (unless a known abbreviation).
    static let lowSignalTokenMaxLength = 3

    /// A single token of 3...this many ASCII letters without a vowel (aeiouy) is noise ("AGBTT").
    static let consonantNoiseMaxLength = 6

    /// A message shorter than this without a digit or a parenthesis has no structure and asks.
    static let structuredMinimumLength = 5

    /// Whether a message is too low-signal to route ("ADD", random letters, empty): the view shows the
    /// clarify card instead of calling the network. Runs BEFORE the on-device intent classification.
    static func shouldAskClarifyingQuestion(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }

        // If it already looks like an import (multi-line, progress/status cues), don't block.
        if TextNormalization.looksLikeImport(t) { return false }

        // Single-token short inputs are most likely noise unless they are known abbreviations.
        let tokens = t.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
        if tokens.count == 1 {
            let s = String(tokens[0])
            let upper = s.uppercased()

            if knownAbbreviations.contains(upper) { return false }

            // Obvious low-signal (very short or command-like).
            if s.count <= lowSignalTokenMaxLength { return true }
            if upper == "ADD" || upper == "IMPORT" { return true }

            // Random letters (no vowels) tends to be noise: "AGBTT".
            if s.count <= consonantNoiseMaxLength,
               s.range(of: #"^[A-Za-z]{3,6}$"#, options: .regularExpression) != nil
            {
                let lower = s.lowercased()
                let hasVowel = lower.contains(where: { "aeiouy".contains($0) })
                if !hasVowel { return true }
            }
        }

        // If it's extremely short and has no structure, ask.
        if t.count < structuredMinimumLength, t.range(of: #"[0-9\(\)]"#, options: .regularExpression) == nil {
            return true
        }

        return false
    }

    // MARK: Intent routing

    /// Minimum on-device (Apple FM) intent confidence to route by it (inclusive); below it, or without a
    /// result, the keyword router decides.
    static let fmIntentMinimumConfidence = 0.65

    /// The flow an on-device intent result picks, or nil when it is not trusted (confidence below
    /// `fmIntentMinimumConfidence`, NaN included): then `keywordFlow(for:)` decides. Intents are compared
    /// exactly: "import" imports, "unknown" asks, anything else (recommend_vibe, recommend_seed,
    /// library_query, club_action) recommends.
    static func onDeviceFlow(intent: String, confidence: Double) -> ConciergeFlow? {
        guard confidence >= fmIntentMinimumConfidence else { return nil }
        switch intent {
        case "import":
            return .importList
        case "unknown":
            return .clarify
        default:
            // recommend_vibe, recommend_seed, library_query, club_action
            return .recommendation
        }
    }

    /// The keyword router (no on-device model, or its result was not trusted): an import when the text
    /// looks like one (`TextNormalization.looksLikeImport`), otherwise a recommendation.
    static func keywordFlow(for text: String) -> ConciergeFlow {
        TextNormalization.looksLikeImport(text) ? .importList : .recommendation
    }

    // MARK: Clarification

    /// Where a clarify-card answer goes: an intent-level answer (kind exactly "intent_unclear") of
    /// "recommend_seed" (any case) switches to the recommendation flow; every other answer re-parses.
    static func clarificationRoute(kind: String, value: String) -> ConciergeClarificationRoute {
        if kind == "intent_unclear" {
            if value.lowercased() == "recommend_seed" {
                return .recommendation
            }
        }
        return .importReparse
    }

    /// The parser's question to show before anything is applied: the first parsed line's ambiguity,
    /// only while the clarify card is enabled (clarify_v2); nil = no clarification step.
    static func parserClarification(in items: [ConciergeParseItem], clarifyEnabled: Bool) -> ConciergeAmbiguity? {
        guard let ambiguity = items.compactMap(\.ambiguity).first, clarifyEnabled else { return nil }
        return ambiguity
    }
}

// MARK: - Input field intent (live chip + paste auto-send)

/// Represents the detected user intent based on input content
enum PrototypeConciergeIntent: Equatable {
    /// No specific intent detected yet
    case unknown
    /// User is importing a list of titles (anime/manga)
    case importList(count: Int)
    /// User is requesting recommendations
    case recommendation

    static func == (lhs: PrototypeConciergeIntent, rhs: PrototypeConciergeIntent) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown):
            return true
        case let (.importList(lhsCount), .importList(rhsCount)):
            return lhsCount == rhsCount
        case (.recommendation, .recommendation):
            return true
        default:
            return false
        }
    }
}

/// Analyzes text input to determine user intent using pattern matching
struct ConciergeIntentDetector {

    // MARK: - Detection Patterns

    /// Keywords that indicate recommendation requests (EN + DE)
    private static let recommendationKeywords = [
        // EN
        "recommend", "suggest", "like", "similar", "vibe", "mood",
        "feeling", "want", "looking for", "need", "any good",
        "what should", "help me find",
        // DE
        "empfehlung", "empfehlen", "vorschlag", "vorschlagen",
        "ähnlich", "aehnlich", "stimmung", "suche", "was soll",
        "hilf mir", "zeig mir", "etwas wie", "so wie",
        "kennst du", "hast du", "gibt es",
    ]

    /// Keywords that indicate import/status intent (single title with verb context)
    private static let importKeywordsEN = [
        "watched", "watching", "finished", "completed", "dropped",
        "paused", "planning", "reading", "read", "started", "begun",
        "on hold", "caught up",
    ]

    private static let importKeywordsDE = [
        "geschaut", "gesehen", "gelesen", "fertig", "abgeschlossen",
        "beendet", "abgebrochen", "pausiert", "geplant", "angefangen",
        "schaue", "gucke", "lese", "noch dabei", "auf eis",
    ]

    /// Patterns that indicate list separators
    private static let listSeparators = [
        "\n",                    // New lines
        ",",                     // Comma
        ";",                     // Semicolon
        "•", "·", "-", "–", "—"  // Bullet points and dashes
    ]

    /// The detected list size is capped here for the chip.
    static let listCountDisplayCap = 99

    // MARK: - Detection Logic

    /// Analyzes text and returns detected intent
    static func detect(from text: String) -> PrototypeConciergeIntent {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty input = unknown intent
        guard !trimmedText.isEmpty else {
            return .unknown
        }

        // Normalize for consistent matching
        let normalized = TextNormalization.normalizeText(trimmedText)

        // Check for list patterns first (prioritize import intent)
        if let listCount = detectListCount(in: trimmedText) {
            return .importList(count: listCount)
        }

        // Check for recommendation keywords (using normalized text)
        if detectRecommendationIntent(in: normalized) {
            return .recommendation
        }

        // Check for import keywords on single-item inputs
        if detectImportIntent(in: normalized) {
            return .importList(count: 1)
        }

        return .unknown
    }

    /// Detects if text contains a list and counts items
    private static func detectListCount(in text: String) -> Int? {
        // Check for multiple lines
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if lines.count >= 2 {
            return min(lines.count, listCountDisplayCap) // Cap at 99 for UI display
        }

        // Check for comma-separated items (at least 2)
        let commaItems = text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if commaItems.count >= 2 {
            return min(commaItems.count, listCountDisplayCap)
        }

        return nil
    }

    /// Checks for recommendation-related keywords (EN + DE)
    private static func detectRecommendationIntent(in text: String) -> Bool {
        let lowercased = text.lowercased()
        let folded = TextNormalization.umlautFold(lowercased)

        return recommendationKeywords.contains { keyword in
            let foldedKeyword = TextNormalization.umlautFold(keyword.lowercased())
            return lowercased.contains(keyword.lowercased()) || folded.contains(foldedKeyword)
        }
    }

    /// Checks for import/status keywords that indicate a single-title import
    private static func detectImportIntent(in text: String) -> Bool {
        let lowercased = text.lowercased()
        let folded = TextNormalization.umlautFold(lowercased)

        let allKeywords = importKeywordsEN + importKeywordsDE
        return allKeywords.contains { keyword in
            let foldedKeyword = TextNormalization.umlautFold(keyword.lowercased())
            return lowercased.contains(keyword) || folded.contains(foldedKeyword)
        }
    }

    // MARK: - Paste auto-send

    /// A text change that grows the input by at least this many characters at once is a paste.
    static let pasteMinimumJump = 20

    /// An import list auto-sends only with at least this many lines (or comma segments).
    static let autoSendMinimumSegments = 2

    /// Whether a text change is a clipboard paste rather than typing (a jump of `pasteMinimumJump`+ characters).
    static func isPaste(previousLength: Int, newText: String) -> Bool {
        (newText.count - previousLength) >= pasteMinimumJump
    }

    /// What a paste auto-sends: the trimmed text, and the fingerprint the field remembers so the same
    /// pasted payload never fires twice.
    struct AutoSend: Equatable {
        let text: String
        let fingerprint: Int
    }

    /// The auto-send of a paste, or nil: only a paste whose detected intent is an import list and whose
    /// text is an import list of 2+ title-like lines (or comma segments). The field still requires that
    /// it is not sending and that the payload's fingerprint differs from the last auto-send.
    static func autoSend(for text: String, intent: PrototypeConciergeIntent, wasPaste: Bool) -> AutoSend? {
        guard wasPaste else { return nil }

        // Only auto-send when the detector is confident this is an import list.
        guard case .importList = intent else { return nil }
        guard looksLikeImportListText(text) else { return nil }

        // Approximate count for dedupe.
        let count = linesOrSegmentsCount(text)

        guard count >= autoSendMinimumSegments else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Prevent double-firing for the same pasted payload.
        return AutoSend(text: trimmed, fingerprint: trimmed.hashValue ^ count)
    }

    /// The number of non-empty lines when there are 2+, otherwise the number of non-empty comma segments.
    static func linesOrSegmentsCount(_ text: String) -> Int {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count >= 2 { return lines.count }

        let commaItems = text
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return commaItems.count
    }

    // NOTE: This is intentionally separate from TextNormalization.looksLikeImport().
    // This function detects multi-item paste lists (2+ segments) for auto-send.
    // TextNormalization.looksLikeImport() handles general intent routing (including single-item imports).
    /// Whether the text is a list of 2+ title-like lines (or, on one line, comma segments).
    static func looksLikeImportListText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count >= 2 {
            let titleCount = lines.filter { segmentLooksTitleLike($0) }.count
            return titleCount >= 2
        }

        let commaItems = trimmed
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if commaItems.count >= 2 {
            let titleCount = commaItems.filter { segmentLooksTitleLike($0) }.count
            return titleCount >= 2
        }

        return false
    }

    /// The input field's title test for one pasted line or segment (case-sensitive; NOT
    /// `TextNormalization.segmentLooksTitleLike`): a unit word, parentheses, 2+ words, a capital
    /// letter or a digit.
    static func segmentLooksTitleLike(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return false }

        if t.range(of: #"\b(ep|episode|chapter|season|staffel|folge|vol|volume)\b"#, options: .regularExpression) != nil {
            return true
        }

        if t.contains("(") && t.contains(")") {
            return true
        }

        let words = t.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if words.count >= 2 { return true }

        if t.range(of: #"[A-Z]"#, options: .regularExpression) != nil { return true }

        return t.range(of: #"\d"#, options: .regularExpression) != nil
    }
}
