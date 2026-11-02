//
//  ConciergeRoutingTests.swift
//  KuroTests
//
//  Characterization of the Concierge's client-side routing rules (`ConciergeRouting`,
//  `ConciergeIntentDetector`), moved out of `ConciergeView` and `ConciergeInputField` (E6). Every
//  expectation is the output of the pre-E6 view code (run verbatim on these inputs before the move),
//  including its quirks, so a change to any rule shows up here: the low-signal gate, the on-device
//  intent threshold (0.65) and intent switch, the keyword router, the intent_unclear re-route, the
//  parser clarification, and the input field's live intent chip and paste auto-send.
//  Inputs reuse the concierge corpora (tests/concierge-corpora/parser_{en,de}.json, router cases) where
//  they apply; these client rules are separate from the `concierge-parse` edge parser, so the corpus
//  `expected_intent` is NOT the expectation (e.g. "planning to watch Vinland Saga" routes to recommend).
//

import Testing
import Foundation
import KuroCore
@testable import Kuro

// MARK: - Case tables (file scope: plain values, no actor isolation)

/// (message, asks) - `ConciergeRouting.shouldAskClarifyingQuestion`.
private let gateCases: [(String, Bool)] = [
    // Empty / whitespace.
    ("", true), ("   ", true), ("\n\t", true),
    // Commands and very short single tokens.
    ("ADD", true), ("add", true), ("IMPORT", true), ("Import", true), ("imports", false),
    ("x", true), ("ok", true), ("ep", true), ("ich", true), ("😀", true), ("(1)", true), ("86", true),
    // Known abbreviations (any case; "," and ";" split tokens) seed instead of asking; others ask.
    ("AOT", false), ("aot", false), ("HxH", false), ("op", false), ("dbz", false), ("eva", false),
    ("SAO,", false), ("AOT;", false), ("JJK", true), ("FMAB", true), ("OPM", true),
    // No-vowel letter runs of 3...6 ask ('y' counts as a vowel; "AGBTT" has an 'A', so it does not ask).
    ("xkcdq", true), ("bcd", true), ("bcdfgh", true), ("bcdfghj", false), ("rhythm", false), ("AGBTT", false),
    // Under 5 characters without a digit or parenthesis asks.
    ("Kiki", true), ("asdf", true), ("K-On", true), ("K-On!", false), ("a b", true), ("was?", true),
    ("ab 1", false), ("1984", false), ("x y z", false), ("12345", false),
    // Umlauts are not ASCII letters: only the length rule applies.
    ("Löwe", true), ("Ödön", true), ("Mönch", false), ("ähnlich", false),
    // Ordinary EN/DE messages and corpus prompts pass to routing.
    ("Bleach", false), ("Frieren", false), ("Hallo", false), ("hilfe", false), ("lustig", false),
    ("Attack on Titan", false), ("Steins;Gate", false), ("zeig mir was", false),
    ("watched it", false), ("geschaut", false), ("at 12", false), ("bei 12", false),
    ("Naruto\nBleach", false), ("S1E2", false),
    // Import-looking text never asks, however short ("band" = Band, a manga volume; any line break).
    ("band", false), ("Band", false), ("a\nb", false), ("x\ny", false),
]

/// (message, routes to import) - `ConciergeRouting.keywordFlow` (EN/DE corpus prompts, actual routing).
private let keywordCases: [(String, Bool)] = [
    ("Attack on Titan completed 10/10", true),
    ("add Naruto watching ep 50", true),
    ("I finished One Piece 9/10", true),
    ("dropped Sword Art Online", true),
    ("planning to watch Vinland Saga", false),
    ("I paused My Hero Academia", true),
    ("JJK completed 8.5/10", true),
    ("Spy x Family S2E8", true),
    ("FMAB 3x12", true),
    ("Bleach 7 out of 10", false),
    ("PTW Spy x Family", false),
    ("Black Clover hiatus", false),
    ("I watched Cowboy Bebop, Trigun, and Samurai Champloo", true),
    ("Dragon Ball Z on hold", false),
    ("Naruto\nBleach", true),
    ("Attack on Titan fertig 10/10", false),
    ("Naruto schaue gerade Folge 50", true),
    ("ich habe Death Note geschaut", true),
    ("ich lese One Punch Man Kapitel 150", true),
    ("angefangen Berserk Band 3", true),
    ("ich habe One Piece vollständig geschaut", true),
    ("ich habe Cowboy Bebop zur Hälfte geschaut", true),
    ("ich habe Cowboy Bebop zur Haelfte geschaut", true),
    ("gedroppt Naruto", false),
    ("Dragon Ball Z auf eis", false),
    ("JJK 9 von 10", false),
    ("Chainsaw Man 8 Punkte", true),
    ("something dark and psychological", false),
    ("like Steins;Gate", false),
    ("recommend something good", false),
    ("what should I watch next", false),
    ("hidden gems I haven't seen", false),
    ("etwas düsteres und psychologisches", false),
    ("ähnlich wie Steins;Gate", false),
    ("empfiehl mir etwas", false),
    ("was soll ich als nächstes schauen", false),
    ("Klassiker die man gesehen haben muss", true),
    ("zeig mir eine Staffel voller Action", true),
    ("ich suche etwas mit 12 Folgen", true),
    ("Attack on Titan", false),
    ("Etwas lustig, trocken, figurengetrieben — nicht kindisch.", false),
    ("Something funny, dry, character-led — not childish.", false),
]

/// (FM intent, confidence, expected flow name; "keywords" = not trusted) - `ConciergeRouting.onDeviceFlow`.
private let onDeviceCases: [(String, Double, String)] = [
    ("import", 0.65, "importList"),
    ("import", 0.6499999999, "keywords"),
    ("import", 0.6500000001, "importList"),
    ("import", 1.0, "importList"),
    ("import", 0.0, "keywords"),
    ("import", .nan, "keywords"),
    ("import", .infinity, "importList"),
    ("import", -.infinity, "keywords"),
    ("unknown", 0.65, "clarify"),
    ("unknown", 0.64, "keywords"),
    ("unknown", .nan, "keywords"),
    ("recommend_vibe", 0.9, "recommendation"),
    ("recommend_seed", 0.65, "recommendation"),
    ("library_query", 0.7, "recommendation"),
    ("club_action", 0.99, "recommendation"),
    ("recommend_vibe", 0.6499999999, "keywords"),
    // Intents are compared exactly: anything that is not "import" / "unknown" recommends.
    ("IMPORT", 0.9, "recommendation"),
    ("Unknown", 0.9, "recommendation"),
    ("import ", 0.9, "recommendation"),
    ("", 0.9, "recommendation"),
]

/// (kind, value, goes to recommend) - `ConciergeRouting.clarificationRoute`.
private let clarificationCases: [(String, String, Bool)] = [
    ("intent_unclear", "recommend_seed", true),
    ("intent_unclear", "RECOMMEND_SEED", true),
    ("intent_unclear", "Recommend_Seed", true),
    ("INTENT_UNCLEAR", "recommend_seed", false),
    ("Intent_Unclear", "recommend_seed", false),
    ("intent_unclear ", "recommend_seed", false),
    ("intent_unclear", "recommend_seed ", false),
    ("intent_unclear", "import", false),
    ("intent_unclear", "recommend_vibe", false),
    ("intent_unclear", "", false),
    ("status_unclear", "recommend_seed", false),
    ("status_unclear", "COMPLETED", false),
    ("unit_unclear", "episode", false),
]

/// (input, detected intent: "unknown" / "recommendation" / "importList(n)") - `ConciergeIntentDetector.detect`.
private let detectCases: [(String, String)] = [
    ("", "unknown"), ("   ", "unknown"), ("Frieren", "unknown"), ("Frieren ist super", "unknown"),
    ("Frieren!!!", "unknown"), ("12345", "unknown"),
    // Lists first: 2+ non-empty lines, else 2+ comma segments (";" and bullets are not separators).
    ("Naruto\nBleach", "importList(2)"), ("Naruto\n\n  \nBleach\nOne Piece", "importList(3)"),
    ("a, b", "importList(2)"), ("Bleach, Naruto", "importList(2)"), ("I liked Frieren, finished it", "importList(2)"),
    ("Steins;Gate", "unknown"), ("Naruto; Bleach", "unknown"), ("Naruto • Bleach", "unknown"),
    // Recommendation keywords before import keywords; plain substring matches ("unlikely" has "like").
    ("I finished Frieren and liked it", "recommendation"), ("unlikely", "recommendation"),
    ("What should I watch?", "recommendation"), ("looking for something dark", "recommendation"),
    ("any good isekai", "recommendation"), ("help me find a show", "recommendation"),
    ("Ähnlich wie Frieren", "recommendation"), ("aehnlich wie Frieren", "recommendation"), ("ähnlich", "recommendation"),
    ("Stimmung: düster", "recommendation"), ("zeig mir was Neues", "recommendation"), ("hilf mir", "recommendation"),
    ("kennst du Frieren", "recommendation"), ("gibt es was wie Frieren", "recommendation"), ("so wie Frieren", "recommendation"),
    ("I want etwas wie Frieren", "recommendation"),
    // Import keywords make a single-title import ("already" contains "read").
    ("already", "importList(1)"), ("I'm watching Frieren", "importList(1)"), ("on hold: Bleach", "importList(1)"),
    ("caught up with JJK", "importList(1)"), ("begun Berserk", "importList(1)"),
    ("Ich habe Frieren gesehen", "importList(1)"), ("ich gucke Spy x Family", "importList(1)"),
    ("Frieren fertig", "importList(1)"), ("abgebrochen: Naruto", "importList(1)"), ("Naruto pausiert", "importList(1)"),
    ("Berserk gelesen", "importList(1)"), ("noch dabei mit Blue Lock", "importList(1)"),
    ("Dragon Ball Z auf Eis", "importList(1)"), ("ich schaue Frieren", "importList(1)"),
]

/// (pasted text, is an import list, lines-or-segments count) - `looksLikeImportListText` / `linesOrSegmentsCount`.
private let listTextCases: [(String, Bool, Int)] = [
    ("Naruto\nBleach", true, 2), ("naruto\nbleach", false, 2), ("naruto ep 5\nbleach", false, 2),
    ("naruto ep 5\nbleach ep 2", true, 2), ("naruto\nbleach 2", false, 2), ("naruto 1\nbleach 2", true, 2),
    ("a, b", false, 2), ("One Piece, Bleach", true, 2), ("one piece, bleach", false, 2), ("Frieren", false, 1),
    ("", false, 0), ("   ", false, 0), ("Naruto (2002)\nbleach", false, 2), ("naruto (tv)\nbleach (tv)", true, 2),
    ("Ep 5\nEp 6", true, 2), ("ep 5\nep 6", true, 2), ("staffel 2\nfolge 3", true, 2), ("Staffel 2\nFolge 3", true, 2),
    ("naruto\nBleach\nonepiece", false, 3), ("Naruto\n\nBleach", true, 2), ("x\ny", false, 2),
    ("Naruto, Bleach\nOne Piece", true, 2),
]

/// (segment, title-like) - the input field's `segmentLooksTitleLike` (case-sensitive; not TextNormalization's).
private let segmentCases: [(String, Bool)] = [
    ("", false), ("a", false), ("ab", false), ("naruto", false), ("Naruto", true), ("naruto ep", true),
    ("naruto ep5", true), ("naruto episode", true), ("Episode", true), ("chapter 3", true), ("naruto chapter", true),
    ("staffel", true), ("folge", true), ("volume", true), ("vol.", true), ("naruto (tv)", true), ("naruto (tv", true),
    ("one piece", true), ("one\tpiece", true), ("naruto2", true), ("ÄÖÜ", false), ("ärger", false), ("  x  ", false),
    ("ep", true),
]

/// (pasted text, expected auto-send text or nil) with the detected intent and `wasPaste == true`.
private let autoSendCases: [(String, String?)] = [
    ("Naruto\nBleach", "Naruto\nBleach"),
    ("  Naruto\nBleach\nOne Piece  ", "Naruto\nBleach\nOne Piece"),
    ("naruto\nbleach", nil),
    ("One Piece, Bleach", "One Piece, Bleach"),
    ("Frieren", nil),
    ("something funny, dry", nil),
    ("Naruto, bleach", nil),
    ("I liked Frieren, finished it", "I liked Frieren, finished it"),
]

// MARK: - Tests

@MainActor
@Suite("Concierge: client routing rules (ConciergeRouting)")
struct ConciergeRoutingTests {

    static func name(_ flow: ConciergeFlow?) -> String {
        guard let flow else { return "keywords" }
        switch flow {
        case .importList: return "importList"
        case .recommendation: return "recommendation"
        case .clarify: return "clarify"
        }
    }

    static func name(_ intent: PrototypeConciergeIntent) -> String {
        switch intent {
        case .unknown: return "unknown"
        case .recommendation: return "recommendation"
        case .importList(let count): return "importList(\(count))"
        }
    }

    // MARK: Low-signal gate

    @Test("Low-signal gate: empty, commands, short tokens, no-vowel runs and structureless short text ask; abbreviations and real messages pass",
          arguments: gateCases)
    func lowSignalGate(text: String, asks: Bool) {
        #expect(ConciergeRouting.shouldAskClarifyingQuestion(text) == asks)
    }

    @Test("Gate thresholds and the abbreviation set are the pre-E6 values")
    func gateThresholds() {
        #expect(ConciergeRouting.lowSignalTokenMaxLength == 3)
        #expect(ConciergeRouting.consonantNoiseMaxLength == 6)
        #expect(ConciergeRouting.structuredMinimumLength == 5)
        #expect(ConciergeRouting.knownAbbreviations == ["AOT", "HXH", "NGE", "EVA", "DB", "DBZ", "DBS", "SAO", "TPN", "BNHA", "OP"])
    }

    @Test("Every import-looking message passes the gate (it is never asked about)")
    func importLookingTextPasses() {
        for (text, isImport) in keywordCases where isImport {
            #expect(!ConciergeRouting.shouldAskClarifyingQuestion(text), "\(text)")
        }
    }

    // MARK: Intent routing

    @Test("On-device intent: trusted at confidence >= 0.65 (NaN never); import / unknown / everything else",
          arguments: onDeviceCases)
    func onDeviceRouting(intent: String, confidence: Double, expected: String) {
        #expect(Self.name(ConciergeRouting.onDeviceFlow(intent: intent, confidence: confidence)) == expected)
    }

    @Test("FM intent threshold is 0.65")
    func fmThreshold() {
        #expect(ConciergeRouting.fmIntentMinimumConfidence == 0.65)
    }

    @Test("Keyword router: TextNormalization.looksLikeImport decides import vs recommend (EN/DE corpus prompts, actual routing)",
          arguments: keywordCases)
    func keywordRouting(text: String, isImport: Bool) {
        let flow = ConciergeRouting.keywordFlow(for: text)
        #expect(flow == (isImport ? .importList : .recommendation))
        #expect(flow != .clarify, "the keyword router never asks")
    }

    // MARK: Clarification

    @Test("Clarify answers: only kind == intent_unclear with value recommend_seed (any case) recommends; everything else re-parses",
          arguments: clarificationCases)
    func clarificationReroute(kind: String, value: String, recommends: Bool) {
        #expect(ConciergeRouting.clarificationRoute(kind: kind, value: value) == (recommends ? .recommendation : .importReparse))
    }

    @Test("Parser clarification: the first parsed line's ambiguity, only while clarify_v2 is on")
    func parserClarification() {
        typealias F = ImportReconcilerTests
        let status = ConciergeAmbiguity(kind: "status_unclear", options: ["COMPLETED", "CURRENT"], suggested_question: "Finished or still watching?", title_context: "Frieren", number_context: nil)
        let unit = ConciergeAmbiguity(kind: "unit_unclear", options: ["episode", "chapter"], suggested_question: nil, title_context: "Berserk", number_context: "12")
        let plain = F.item("Naruto ep 3", candidates: [F.candidate(.anime, 1)])
        let first = F.item("I watched Frieren", candidates: [F.candidate(.anime, 2)], ambiguity: status)
        let second = F.item("Berserk 12", candidates: [F.candidate(.manga, 3)], ambiguity: unit)

        #expect(ConciergeRouting.parserClarification(in: [], clarifyEnabled: true) == nil)
        #expect(ConciergeRouting.parserClarification(in: [plain], clarifyEnabled: true) == nil)
        #expect(ConciergeRouting.parserClarification(in: [plain, first, second], clarifyEnabled: true)?.kind == "status_unclear")
        #expect(ConciergeRouting.parserClarification(in: [plain, second, first], clarifyEnabled: true)?.kind == "unit_unclear")
        #expect(ConciergeRouting.parserClarification(in: [plain, first, second], clarifyEnabled: false) == nil)
        #expect(ConciergeRouting.parserClarification(in: [plain], clarifyEnabled: false) == nil)
    }

    // MARK: Input field: live intent

    @Test("Input field intent: lists first, then recommendation keywords, then import keywords (EN/DE, umlauts folded)",
          arguments: detectCases)
    func inputIntent(text: String, expected: String) {
        #expect(Self.name(ConciergeIntentDetector.detect(from: text)) == expected)
    }

    @Test("Input field intent: the list size shown is capped at 99")
    func listCountCap() {
        let titles = (1...120).map { "Title \($0)" }
        #expect(ConciergeIntentDetector.detect(from: titles.joined(separator: "\n")) == .importList(count: 99))
        #expect(ConciergeIntentDetector.detect(from: titles.joined(separator: ", ")) == .importList(count: 99))
        #expect(ConciergeIntentDetector.detect(from: titles.prefix(99).joined(separator: "\n")) == .importList(count: 99))
        #expect(ConciergeIntentDetector.detect(from: titles.prefix(98).joined(separator: "\n")) == .importList(count: 98))
        #expect(ConciergeIntentDetector.listCountDisplayCap == 99)
    }

    // MARK: Input field: paste auto-send

    @Test("A paste is a jump of 20+ characters at once (typing and deleting are not)")
    func pasteDetection() {
        let nineteen = String(repeating: "a", count: 19)
        let twenty = String(repeating: "a", count: 20)
        let twentyFive = String(repeating: "a", count: 25)
        #expect(!ConciergeIntentDetector.isPaste(previousLength: 0, newText: nineteen))
        #expect(ConciergeIntentDetector.isPaste(previousLength: 0, newText: twenty))
        #expect(ConciergeIntentDetector.isPaste(previousLength: 5, newText: twentyFive))
        #expect(!ConciergeIntentDetector.isPaste(previousLength: 6, newText: twentyFive))
        #expect(!ConciergeIntentDetector.isPaste(previousLength: 30, newText: twentyFive))
        #expect(!ConciergeIntentDetector.isPaste(previousLength: 0, newText: ""))
        #expect(ConciergeIntentDetector.isPaste(previousLength: 0, newText: "Naruto\nBleach\nOne Piece"))
        #expect(ConciergeIntentDetector.pasteMinimumJump == 20)
        #expect(ConciergeIntentDetector.autoSendMinimumSegments == 2)
    }

    @Test("Pasted import list: 2+ title-like lines (else comma segments); the count is lines when 2+, else segments",
          arguments: listTextCases)
    func pastedListText(text: String, isList: Bool, count: Int) {
        #expect(ConciergeIntentDetector.looksLikeImportListText(text) == isList)
        #expect(ConciergeIntentDetector.linesOrSegmentsCount(text) == count)
    }

    @Test("Pasted segment is title-like: unit word, parentheses, 2+ words, a capital or a digit (case-sensitive)",
          arguments: segmentCases)
    func pastedSegment(text: String, titleLike: Bool) {
        #expect(ConciergeIntentDetector.segmentLooksTitleLike(text) == titleLike)
    }

    @Test("Paste auto-send: only a paste detected as an import list that is a list of 2+ title-like lines; sends the trimmed text",
          arguments: autoSendCases)
    func pasteAutoSend(text: String, expected: String?) throws {
        let intent = ConciergeIntentDetector.detect(from: text)
        let send = ConciergeIntentDetector.autoSend(for: text, intent: intent, wasPaste: true)
        #expect(send?.text == expected)
        if let expected {
            let unwrapped = try #require(send)
            #expect(unwrapped.fingerprint == expected.hashValue ^ ConciergeIntentDetector.linesOrSegmentsCount(text), "same payload, same fingerprint")
        }
        // Typing (not a paste) never auto-sends.
        #expect(ConciergeIntentDetector.autoSend(for: text, intent: intent, wasPaste: false) == nil)
    }

    @Test("Paste auto-send needs the import-list intent (its count is not used); the text decides the rest")
    func pasteAutoSendIntentGate() {
        let list = "Naruto\nBleach"
        #expect(ConciergeIntentDetector.autoSend(for: list, intent: .recommendation, wasPaste: true) == nil)
        #expect(ConciergeIntentDetector.autoSend(for: list, intent: .unknown, wasPaste: true) == nil)
        #expect(ConciergeIntentDetector.autoSend(for: list, intent: .importList(count: 1), wasPaste: true)?.text == list)
        #expect(ConciergeIntentDetector.autoSend(for: "naruto\nbleach", intent: .importList(count: 2), wasPaste: true) == nil)
        #expect(ConciergeIntentDetector.autoSend(for: "", intent: .importList(count: 2), wasPaste: true) == nil)
    }
}

@Suite("Concierge workflow lifetime")
@MainActor
struct ConciergeWorkflowLifetimeTests {
    @Test("A non-cooperative intent result cannot dispatch fallback after account/chat/view changes",
          arguments: ["account", "chat", "disappear"])
    func heldIntent(scopeChange: String) async throws {
        let session = AccountSessionCoordinator()
        _ = session.begin(userId: "account-a")
        let lifetime = ConciergeWorkflowLifetime()
        lifetime.activate(session: session)
        let origin = lifetime.capture(session: session)
        var heldIntent: CheckedContinuation<String?, Never>?
        var privateDispatches = 0
        let action = try #require(lifetime.launch(origin: origin, session: session) {
            // Foundation Models may return nil despite cancellation. The same post-await fence
            // used by the view must reject that result before parsing/recommending under a new scope.
            let _: String? = await withCheckedContinuation { heldIntent = $0 }
            guard lifetime.isCurrent(ConciergeWorkflowScope.ticket, session: session) else { return }
            privateDispatches += 1
        })
        while heldIntent == nil { await Task.yield() }
        switch scopeChange {
        case "account": _ = session.begin(userId: "account-b")
        case "chat": lifetime.invalidate()
        default: lifetime.deactivate()
        }
        if scopeChange != "chat" {
            #expect(lifetime.capture(session: session) == nil, "old mounted UI cannot admit a new-account action")
        }
        heldIntent?.resume(returning: nil)
        await action.value
        #expect(privateDispatches == 0)
        #expect(lifetime.launch(origin: origin, session: session) { privateDispatches += 1 } == nil)

        // A new user gesture still works; the fence does not leave the chat permanently blocked.
        lifetime.activate(session: session)
        let fresh = try #require(lifetime.launch(origin: lifetime.capture(session: session), session: session) {
            guard lifetime.isCurrent(ConciergeWorkflowScope.ticket, session: session) else { return }
            privateDispatches += 1
        })
        await fresh.value
        #expect(privateDispatches == 1)
    }
}
