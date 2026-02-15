// MARK: - ConciergeInputField.swift
// Concierge input field with intent detection and paste cues.
// Designed to be lightweight: no per-keystroke haptics, minimal animations.

import SwiftUI
import UIKit

// MARK: - Concierge Smart Suggestions (Lightweight)

private struct ConciergeSuggestion: Identifiable, Hashable {
    enum Kind: Hashable {
        case template(String)
        case append(String)
    }

    let id = UUID()
    let systemImage: String
    let title: String
    let kind: Kind
}

private struct ConciergeSuggestionBar: View {
    let suggestions: [ConciergeSuggestion]
    let onTap: (ConciergeSuggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { s in
                    Button(action: { onTap(s) }) {
                        HStack(spacing: 6) {
                            Image(systemName: s.systemImage)
                                .font(.kuroCaption(weight: .semibold))
                            Text(s.title)
                                .font(.kuroCaption(weight: .medium))
                                .tracking(0.6)
                        }
                        .foregroundStyle(.primary.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - PrototypeConciergeIntent Enum

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

// MARK: - Haptics Manager

/// Centralized haptic feedback manager for consistent tactile responses
@MainActor
final class ConciergeHapticsManager {
    static let shared = ConciergeHapticsManager()
    
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    private init() {
        // Prepare generators for immediate response
        lightImpact.prepare()
        mediumImpact.prepare()
        notificationFeedback.prepare()
    }
    
    /// Medium haptic feedback for send action
    func send() {
        mediumImpact.impactOccurred(intensity: 0.7)
        mediumImpact.prepare()
    }
    
    /// Success feedback for paste detection
    func pasteSuccess() {
        notificationFeedback.notificationOccurred(.success)
        notificationFeedback.prepare()
    }
}

// MARK: - Intent Detector

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
            return min(lines.count, 99) // Cap at 99 for UI display
        }

        // Check for comma-separated items (at least 2)
        let commaItems = text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if commaItems.count >= 2 {
            return min(commaItems.count, 99)
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
}

// MARK: - Detected List Chip View

/// Floating chip showing detected list count above input
struct DetectedListChip: View {
    let count: Int
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.kuroCaption(weight: .medium))

            Text("\(count) \(count == 1 ? "title" : "titles") detected")
                .font(.kuroCaption(weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.kuroSecondaryBackground.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? -8 : 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) {
                isVisible = true
            }
        }
        .onTapGesture {
            onDismiss()
        }
    }
}

// MARK: - Intent Indicator View

/// Shows the current detected intent with icon and animation
struct IntentIndicator: View {
    let intent: PrototypeConciergeIntent
    
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1
    
    var body: some View {
        Group {
            switch intent {
            case .importList(let count):
                importIndicator(count: count)
            case .recommendation:
                recommendationIndicator
            case .unknown:
                EmptyView()
            }
        }
        .onChange(of: intent) { _, _ in
            animateTransition()
        }
    }
    
    private func importIndicator(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.on.clipboard")
                .font(.kuroCaption(weight: .medium))

            if count > 0 {
                Text("\(count)")
                    .font(.kuroCaption(weight: .bold))
            }
        }
        .foregroundStyle(.black.opacity(0.50))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.06))
        )
        .scaleEffect(scale)
    }
    
    private var recommendationIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.kuroCaption(weight: .medium))
        }
        .foregroundStyle(.black.opacity(0.50))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.06))
        )
        .scaleEffect(scale)
    }
    
    private func animateTransition() {
        withAnimation(.easeOut(duration: 0.12)) {
            scale = 1.06
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.12)) {
                scale = 1.0
            }
        }
    }
}

// MARK: - Main Input Field View

/// The magical Concierge input field with dynamic behaviors
struct ConciergeInputField: View {
    
    // MARK: - Bindings
    
    @Binding var text: String
    var isSending: Bool = false
    var focusRequest: Binding<Bool>? = nil
    var onSend: (_ text: String) -> Void
    /// Optional: when we detect a paste that clearly looks like an import list, auto-trigger send.
    /// This keeps the flow "magic" without an extra button press.
    var onAutoSend: ((_ text: String) -> Void)? = nil
    var detectedIntent: Binding<PrototypeConciergeIntent>?
    
    // MARK: - State
    
    @State private var internalIntent: PrototypeConciergeIntent = .unknown
    @FocusState private var isInputFocused: Bool
    @State private var showDetectedChip = false
    @State private var detectedCount = 0
    @State private var lastTextLength = 0
    @State private var suggestions: [ConciergeSuggestion] = []
    @State private var suggestionTask: Task<Void, Never>? = nil
    @State private var detectedChipTask: Task<Void, Never>? = nil
    @State private var measuredTextHeight: CGFloat = 20
    @State private var lastAutoSentTextFingerprint: Int? = nil
    
    // MARK: - Constants
    
    private enum Constants {
        static let cornerRadius: CGFloat = 20
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 12
        static let maxHeight: CGFloat = 120
        static let collapsedMaxHeight: CGFloat = 38
        static let lineHeight: CGFloat = 20
    }
    
    // MARK: - Computed Properties
    
    private var currentIntent: PrototypeConciergeIntent {
        detectedIntent?.wrappedValue ?? internalIntent
    }
    
    private var characterCount: Int {
        text.count
    }

    private var isGermanLocale: Bool {
        let language = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        return language.hasPrefix("de")
    }
    
    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var canSend: Bool {
        !isEmpty && !isSending
    }

    private var isImportIntent: Bool {
        if case .importList = currentIntent { return true }
        return false
    }
    
    /// Dynamic opacity based on content length
    private var inputOpacity: Double {
        if isEmpty {
            return 0.28
        } else if characterCount <= 2 {
            return 0.80
        } else {
            return 0.90
        }
    }

    private var inputMaxHeight: CGFloat {
        (isInputFocused || !isEmpty) ? Constants.maxHeight : Constants.collapsedMaxHeight
    }

    private var uiFont: UIFont {
        let base = UIFont.systemFont(ofSize: 17, weight: .regular)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: 17)
    }
    
    // MARK: - Body
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if isEmpty {
                    placeholderView
                }

                KuroGrowingTextView(
                    text: $text,
                    isFocused: Binding(
                        get: { isInputFocused },
                        set: { isInputFocused = $0 }
                    ),
                    measuredHeight: $measuredTextHeight,
                    font: uiFont,
                    textColor: UIColor.black.withAlphaComponent(0.85),
                    maxHeight: inputMaxHeight
                )
                .frame(height: min(inputMaxHeight, max(Constants.lineHeight, measuredTextHeight)))
                .onChange(of: text) { oldValue, newValue in
                    handleTextChange(from: oldValue, to: newValue)
                }
            }

            sendButton
        }
        .padding(.vertical, 6)
        .onAppear {
            updateSuggestionsDebounced(text)
        }
        .onDisappear {
            suggestionTask?.cancel()
            detectedChipTask?.cancel()
        }
        .onChange(of: focusRequest?.wrappedValue ?? false) { _, wantsFocus in
            guard wantsFocus else { return }
            isInputFocused = true
            // Best-effort reset so repeated taps re-focus.
            focusRequest?.wrappedValue = false
        }
    }
    
    // MARK: - Subviews
    
    private var placeholderView: some View {
        Text("Ask Whisper...")
            .font(.system(size: 17, weight: .regular, design: .serif))
            .italic()
            .foregroundStyle(Color.black.opacity(0.35))
            .padding(.top, 2)
    }
    
    private var sendButton: some View {
        Button(action: handleSend) {
            Image(systemName: "paperplane")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.black.opacity(canSend ? 0.55 : 0.28))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.black.opacity(canSend ? 0.06 : 0.03))
                )
        }
        .disabled(!canSend)
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func handleTextChange(from oldValue: String, to newValue: String) {
        // Detect intent
        let newIntent = ConciergeIntentDetector.detect(from: newValue)

        if let binding = detectedIntent {
            binding.wrappedValue = newIntent
        } else {
            internalIntent = newIntent
        }

        // Detect paste: a large text jump (20+ chars) indicates clipboard paste vs typing.
        let wasPaste = (newValue.count - lastTextLength) >= 20

        // Handle list detection chip
        handleListDetection(intent: newIntent, wasPaste: wasPaste)
        maybeAutoSend(intent: newIntent, wasPaste: wasPaste, text: newValue)

        lastTextLength = newValue.count

        updateSuggestionsDebounced(newValue)
    }

    private func maybeAutoSend(intent: PrototypeConciergeIntent, wasPaste: Bool, text: String) {
        guard wasPaste else { return }
        guard !isSending else { return }
        guard let onAutoSend else { return }

        // Only auto-send when the detector is confident this is an import list.
        guard case .importList = intent else { return }
        guard looksLikeImportListText(text) else { return }

        // Approximate count for dedupe.
        let count = linesOrSegmentsCount(text)

        guard count >= 2 else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Prevent double-firing for the same pasted payload.
        let fp = trimmed.hashValue ^ count
        if lastAutoSentTextFingerprint == fp { return }
        lastAutoSentTextFingerprint = fp

        onAutoSend(trimmed)
    }

    private func linesOrSegmentsCount(_ text: String) -> Int {
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

    private func looksLikeImportListText(_ text: String) -> Bool {
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

    private func segmentLooksTitleLike(_ text: String) -> Bool {
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

    private func pasteFromClipboard() {
        let pasted = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pasted.isEmpty else { return }
        ConciergeHapticsManager.shared.pasteSuccess()
        text = pasted
        focusRequest?.wrappedValue = true

        let intent = ConciergeIntentDetector.detect(from: pasted)
        maybeAutoSend(intent: intent, wasPaste: true, text: pasted)
    }

    private func updateSuggestionsDebounced(_ text: String) {
        suggestionTask?.cancel()
        suggestionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            suggestions = buildSuggestions(text: text, intent: currentIntent)
        }
    }

    private func buildSuggestions(text: String, intent: PrototypeConciergeIntent) -> [ConciergeSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if trimmed.isEmpty {
            if isGermanLocale {
                return [
                    .init(systemImage: "film", title: "Ein perfekter Film", kind: .append("ein perfekter anime-film")),
                    .init(systemImage: "sparkles", title: "Die Auswahl", kind: .template("Kuratiere mir etwas Neues. Sauber, nicht kindisch.")),
                    .init(systemImage: "moon.stars", title: "Sanft", kind: .append("sanft, ruhig, wohltuend")),
                    .init(systemImage: "eye", title: "Dunkel, nicht leer", kind: .append("dunkel, ernst, ohne gore")),
                    .init(systemImage: "crown", title: "Der Kanon", kind: .append("klassiker")),
                    .init(systemImage: "minus.circle", title: "Ohne Romance", kind: .append("ohne romance"))
                ]
            }
            return [
                .init(systemImage: "film", title: "One perfect film", kind: .append("one perfect anime film")),
                .init(systemImage: "sparkles", title: "The Cut", kind: .template("Curate something new to me. Clean, not childish.")),
                .init(systemImage: "moon.stars", title: "Soft", kind: .append("soft, quiet, restorative")),
                .init(systemImage: "eye", title: "Dark, not empty", kind: .append("dark, serious, not gory")),
                .init(systemImage: "crown", title: "The Canon", kind: .append("classics")),
                .init(systemImage: "minus.circle", title: "No romance", kind: .append("no romance"))
            ]
        }

        switch intent {
        case .importList:
            return []
        case .recommendation, .unknown:
            var out: [ConciergeSuggestion] = []
            if isGermanLocale {
                if !lower.contains("ohne romance") && !lower.contains("ohne romanze") {
                    out.append(.init(systemImage: "minus.circle", title: "Ohne Romance", kind: .append("ohne romance")))
                }
                if !lower.contains("ohne isekai") {
                    out.append(.init(systemImage: "minus.circle", title: "Ohne Isekai", kind: .append("ohne isekai")))
                }
                if !lower.contains("kurz") && !lower.contains("eine staffel") {
                    out.append(.init(systemImage: "bolt", title: "Kurz", kind: .append("kurz eine staffel")))
                }
                if !lower.contains("klassiker") && !lower.contains("klassisch") {
                    out.append(.init(systemImage: "crown", title: "Der Kanon", kind: .append("klassiker")))
                }
                if out.isEmpty {
                    out.append(.init(systemImage: "sparkles", title: "Neu für mich", kind: .append("neu für mich")))
                }
                return Array(out.prefix(6))
            }

            if !lower.contains("no romance") { out.append(.init(systemImage: "minus.circle", title: "No romance", kind: .append("no romance"))) }
            if !lower.contains("no isekai") { out.append(.init(systemImage: "minus.circle", title: "No isekai", kind: .append("no isekai"))) }
            if !lower.contains("short") && !lower.contains("one season") { out.append(.init(systemImage: "bolt", title: "Short", kind: .append("short one season"))) }
            if !lower.contains("classic") { out.append(.init(systemImage: "crown", title: "The Canon", kind: .append("classics"))) }
            if out.isEmpty { out.append(.init(systemImage: "sparkles", title: "New to me", kind: .append("new to me"))) }
            return Array(out.prefix(6))
        }
    }

    private func applySuggestion(_ suggestion: ConciergeSuggestion) {
        KuroAccessibility.impactHaptic(.light)

        switch suggestion.kind {
        case .template(let t):
            text = t
        case .append(let fragment):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                text = fragment
            } else if trimmed.hasSuffix(",") || trimmed.hasSuffix(" ") {
                text = trimmed + fragment
            } else {
                text = trimmed + ", " + fragment
            }
        }

        // Keep focus on input after chip tap.
        focusRequest?.wrappedValue = true
        updateSuggestionsDebounced(text)
    }
    
    private func handleListDetection(intent: PrototypeConciergeIntent, wasPaste: Bool) {
        switch intent {
        case .importList(let count):
            if count != detectedCount || !showDetectedChip {
                detectedCount = count
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showDetectedChip = true
                }
                scheduleDetectedChipDismiss()
                // Only fire paste haptic on actual paste, not on typing commas/newlines.
                if wasPaste {
                    ConciergeHapticsManager.shared.pasteSuccess()
                }
            }
        default:
            detectedChipTask?.cancel()
            if showDetectedChip {
                withAnimation(.easeOut(duration: 0.2)) {
                    showDetectedChip = false
                }
            }
        }
    }

    private func scheduleDetectedChipDismiss() {
        detectedChipTask?.cancel()
        detectedChipTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showDetectedChip = false
            }
        }
    }
    
    private func handleSend() {
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !payload.isEmpty else { return }
        
        // Medium haptic on send
        ConciergeHapticsManager.shared.send()
        
        // Call the send action
        onSend(payload)
        
        // Reset state
        withAnimation(.spring(response: 0.3)) {
            text = ""
            showDetectedChip = false
            if detectedIntent == nil {
                internalIntent = .unknown
            }
        }
        suggestionTask?.cancel()
        suggestions = []
        detectedChipTask?.cancel()
    }
    
}

// MARK: - UIKit Growing Text View (Collapsed -> Expands on Focus)

private struct KuroGrowingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat
    let font: UIFont
    let textColor: UIColor
    let maxHeight: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.font = font
        tv.textColor = textColor
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.font != font {
            uiView.font = font
        }
        if uiView.textColor != textColor {
            uiView.textColor = textColor
        }

        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }

        DispatchQueue.main.async {
            context.coordinator.updateHeight(uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: KuroGrowingTextView
        init(parent: KuroGrowingTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            updateHeight(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if parent.isFocused == false { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused == true { parent.isFocused = false }
        }

        func updateHeight(_ textView: UITextView) {
            let width = max(1, textView.bounds.width)
            let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            let size = textView.sizeThatFits(targetSize)
            let clamped = min(parent.maxHeight, max(20, size.height))
            if abs(parent.measuredHeight - clamped) > 0.5 {
                parent.measuredHeight = clamped
            }
            textView.isScrollEnabled = size.height > parent.maxHeight
        }
    }
}

// MARK: - Send Button Style

/// Custom button style for send button with scale animation
struct ConciergeSendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#if DEBUG
// MARK: - Preview

#Preview("Empty State") {
    ConciergeInputFieldPreviewContainer()
}

#Preview("Import Intent") {
    ConciergeInputFieldPreviewContainer(
        initialText: "Naruto\nOne Piece\nBleach\nDeath Note"
    )
}

private struct ConciergeInputFieldPreviewContainer: View {
    @State private var text: String
    @State private var detectedIntent: PrototypeConciergeIntent = .unknown

    init(initialText: String = "") {
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(spacing: 10) {
            if detectedIntent != .unknown {
                Text("Detected: \(intentDescription)")
                    .font(.kuroCaption())
                    .foregroundStyle(.secondary)
            }

            ConciergeInputField(
                text: $text,
                onSend: { _ in },
                detectedIntent: $detectedIntent
            )
        }
        .padding()
        .background(Color.kuroBackground)
    }

    private var intentDescription: String {
        switch detectedIntent {
        case .unknown: return "Unknown"
        case .importList(let count): return "Import (\(count) items)"
        case .recommendation: return "Recommendation"
        }
    }
}
#endif
