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
    
    /// Keywords that indicate recommendation requests
    private static let recommendationKeywords = [
        "recommend", "suggest", "like", "similar", "vibe", "mood",
        "feeling", "want", "looking for", "need", "any good",
        "what should", "help me find"
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
        
        // Check for list patterns first (prioritize import intent)
        if let listCount = detectListCount(in: trimmedText) {
            return .importList(count: listCount)
        }
        
        // Check for recommendation keywords
        if detectRecommendationIntent(in: trimmedText) {
            return .recommendation
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
    
    /// Checks for recommendation-related keywords
    private static func detectRecommendationIntent(in text: String) -> Bool {
        let lowercased = text.lowercased()
        
        return recommendationKeywords.contains { keyword in
            lowercased.contains(keyword.lowercased())
        }
    }
}

// MARK: - Detected List Chip View

/// Floating chip showing detected list count above input
struct DetectedListChip: View {
    let count: Int
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    @State private var bounceOffset: CGFloat = 0
    
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
        .offset(y: bounceOffset)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? -8 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isVisible = true
            }
            
            // Bounce animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    bounceOffset = -4
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        bounceOffset = 0
                    }
                }
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            scale = 1.2
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
    var detectedIntent: Binding<PrototypeConciergeIntent>?
    
    // MARK: - State
    
    @State private var internalIntent: PrototypeConciergeIntent = .unknown
    @State private var isPlaceholderVisible = true
    @State private var placeholderOpacity: Double = 0.3
    @FocusState private var isInputFocused: Bool
    @State private var showDetectedChip = false
    @State private var detectedCount = 0
    @State private var lastTextLength = 0
    @State private var suggestions: [ConciergeSuggestion] = []
    @State private var suggestionTask: Task<Void, Never>? = nil
    
    // MARK: - Constants
    
    private enum Constants {
        static let cornerRadius: CGFloat = 20
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 12
        static let maxHeight: CGFloat = 120
        static let lineHeight: CGFloat = 20
    }
    
    // MARK: - Computed Properties
    
    private var currentIntent: PrototypeConciergeIntent {
        detectedIntent?.wrappedValue ?? internalIntent
    }
    
    private var characterCount: Int {
        text.count
    }
    
    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var canSend: Bool {
        !isEmpty && !isSending
    }
    
    /// Dynamic opacity based on content length
    private var inputOpacity: Double {
        if isEmpty {
            return 0.30
        } else if characterCount <= 2 {
            return 0.80
        } else {
            return 0.90
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !suggestions.isEmpty {
                ConciergeSuggestionBar(suggestions: suggestions, onTap: applySuggestion)
                    .transition(.opacity)
            }

            // Main input container
            HStack(alignment: .bottom, spacing: 12) {
                    // Input area with placeholder
                    ZStack(alignment: .topLeading) {
                        // Placeholder text with pulsing animation
                        if isEmpty {
                            placeholderView
                        }

                        // Text input
                        TextEditor(text: $text)
                            .font(.kuroBody())
                            .foregroundStyle(Color.primary.opacity(inputOpacity))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(minHeight: Constants.lineHeight, maxHeight: Constants.maxHeight)
                            .focused($isInputFocused)
                            .onChange(of: text) { oldValue, newValue in
                                handleTextChange(from: oldValue, to: newValue)
                            }
                    }

                    // Intent indicator (if detected)
                    if currentIntent != .unknown {
                        IntentIndicator(intent: currentIntent)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Send button
                    sendButton
                }
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.vertical, Constants.verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: Constants.cornerRadius)
                        .fill(Color.kuroSecondaryBackground.opacity(0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                                .stroke(
                                    Color.primary.opacity(0.10),
                                    lineWidth: 0.6
                                )
                        )
                )
                .overlay(alignment: .topLeading) {
                    // Detected list chip (anchored to input, not floating mid-screen)
                    if showDetectedChip {
                        DetectedListChip(count: detectedCount) {
                            withAnimation(.spring(response: 0.3)) {
                                showDetectedChip = false
                            }
                        }
                        .offset(x: 8, y: -44)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
        }
        .onAppear {
            startPlaceholderPulse()
            updateSuggestionsDebounced(text)
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
        Text("Paste titles, or describe a mood...")
            .font(.kuroBody())
            .foregroundStyle(Color.primary.opacity(placeholderOpacity))
            .padding(.top, 2)
            .onAppear {
                startPlaceholderPulse()
            }
    }
    
    private var sendButton: some View {
        Button(action: handleSend) {
            Image(systemName: "arrow.up")
                .font(.kuroCaption(weight: .medium))
                .foregroundStyle(canSend ? .white : Color.black.opacity(0.18))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(canSend ? Color.black.opacity(0.88) : Color.black.opacity(0.04))
                )
        }
        .disabled(!canSend)
        .buttonStyle(ConciergeSendButtonStyle())
        .padding(.bottom, 2)
    }
    
    // MARK: - Actions
    
    private func handleTextChange(from oldValue: String, to newValue: String) {
        // Update placeholder visibility
        withAnimation(.easeInOut(duration: 0.2)) {
            isPlaceholderVisible = newValue.isEmpty
        }

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

        lastTextLength = newValue.count

        updateSuggestionsDebounced(newValue)
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
            return [
                .init(systemImage: "sparkles", title: "Premium", kind: .template("Recommend something premium, clean, not childish.")),
                .init(systemImage: "theatermasks", title: "Comedy", kind: .append("comedy")),
                .init(systemImage: "moon.stars", title: "Cozy", kind: .append("cozy")),
                .init(systemImage: "eye", title: "Dark", kind: .append("dark, serious")),
                .init(systemImage: "film", title: "Movie", kind: .append("movie")),
                .init(systemImage: "minus.circle", title: "No romance", kind: .append("no romance"))
            ]
        }

        switch intent {
        case .importList:
            return [
                .init(systemImage: "checkmark.seal", title: "Confirm", kind: .template(trimmed)),
                .init(systemImage: "gobackward", title: "Re-parse", kind: .template(trimmed))
            ]
        case .recommendation, .unknown:
            var out: [ConciergeSuggestion] = []
            if !lower.contains("no romance") { out.append(.init(systemImage: "minus.circle", title: "No romance", kind: .append("no romance"))) }
            if !lower.contains("no isekai") { out.append(.init(systemImage: "minus.circle", title: "No isekai", kind: .append("no isekai"))) }
            if !lower.contains("short") && !lower.contains("one season") { out.append(.init(systemImage: "bolt", title: "Short", kind: .append("short one season"))) }
            if !lower.contains("classic") { out.append(.init(systemImage: "crown", title: "Classics", kind: .append("classics"))) }
            if out.isEmpty { out.append(.init(systemImage: "sparkles", title: "Premium", kind: .append("premium"))) }
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
                // Only fire paste haptic on actual paste, not on typing commas/newlines.
                if wasPaste {
                    ConciergeHapticsManager.shared.pasteSuccess()
                }
            }
        default:
            if showDetectedChip {
                withAnimation(.easeOut(duration: 0.2)) {
                    showDetectedChip = false
                }
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
    }
    
    // MARK: - Animation
    
    private func startPlaceholderPulse() {
        // Static opacity — no repeatForever animation on the input field.
        placeholderOpacity = 0.45
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
