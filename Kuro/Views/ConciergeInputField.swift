#if DEBUG
// MARK: - ConciergeInputField.swift
// NOTE: Experimental Concierge prototype UI (debug-only).
//
// A magical chat input field with dynamic typography, intent detection,
// haptic feedback, and smart paste capabilities for the Concierge feature.

import SwiftUI
import UIKit

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
    
    /// Light haptic feedback for character input
    func characterInput() {
        lightImpact.impactOccurred(intensity: 0.4)
        lightImpact.prepare()
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
                .font(.system(size: 12, weight: .medium))
            
            Text("\(count) \(count == 1 ? "title" : "titles") detected")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
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
                .font(.system(size: 12, weight: .medium))
            
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.blue.opacity(0.15))
        )
        .scaleEffect(scale)
    }
    
    private var recommendationIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.15))
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
    var onSend: () -> Void
    var detectedIntent: Binding<PrototypeConciergeIntent>?
    
    // MARK: - State
    
    @State private var internalIntent: PrototypeConciergeIntent = .unknown
    @State private var isPlaceholderVisible = true
    @State private var placeholderOpacity: Double = 0.3
    @FocusState private var isInputFocused: Bool
    @State private var showDetectedChip = false
    @State private var detectedCount = 0
    @State private var lastTextLength = 0
    
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
        !isEmpty
    }
    
    /// Dynamic typography based on content length
    private var inputFont: Font {
        let weight: Font.Weight = characterCount >= 3 ? .regular : .light
        return .system(size: 15, weight: weight, design: .default)
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
        ZStack(alignment: .bottom) {
            // Detected list chip (floating above input)
            if showDetectedChip {
                VStack(spacing: 0) {
                    DetectedListChip(count: detectedCount) {
                        withAnimation(.spring(response: 0.3)) {
                            showDetectedChip = false
                        }
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
                        .font(inputFont)
                        .foregroundStyle(.primary.opacity(inputOpacity))
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
                // Glass morphism background
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Gradient border
                        RoundedRectangle(cornerRadius: Constants.cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
            .shadow(
                color: .black.opacity(0.06),
                radius: 12,
                x: 0,
                y: 4
            )
        }
        .onAppear {
            startPlaceholderPulse()
        }
    }
    
    // MARK: - Subviews
    
    private var placeholderView: some View {
        Text("Ask Concierge anything...")
            .font(.system(size: 15, weight: .light))
            .foregroundStyle(.primary.opacity(placeholderOpacity))
            .padding(.top, 2)
            .onAppear {
                startPlaceholderPulse()
            }
    }
    
    private var sendButton: some View {
        Button(action: handleSend) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(canSend ? Color.primary : Color.primary.opacity(0.2))
                .contentShape(Circle())
        }
        .disabled(!canSend)
        .buttonStyle(ConciergeSendButtonStyle())
        .padding(.bottom, 2)
    }
    
    // MARK: - Actions
    
    private func handleTextChange(from oldValue: String, to newValue: String) {
        // Haptic feedback on character input
        if newValue.count > oldValue.count {
            ConciergeHapticsManager.shared.characterInput()
        }
        
        // Update placeholder visibility
        withAnimation(.easeInOut(duration: 0.2)) {
            isPlaceholderVisible = newValue.isEmpty
        }
        
        // Detect intent
        let newIntent = ConciergeIntentDetector.detect(from: newValue)
        
        if let binding = detectedIntent {
            binding.wrappedValue = newIntent
        } else {
            withAnimation(.spring(response: 0.3)) {
                internalIntent = newIntent
            }
        }
        
        // Handle list detection chip
        handleListDetection(intent: newIntent)
        
        lastTextLength = newValue.count
    }
    
    private func handleListDetection(intent: PrototypeConciergeIntent) {
        switch intent {
        case .importList(let count):
            if count != detectedCount || !showDetectedChip {
                detectedCount = count
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showDetectedChip = true
                }
                ConciergeHapticsManager.shared.pasteSuccess()
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
        guard canSend else { return }
        
        // Medium haptic on send
        ConciergeHapticsManager.shared.send()
        
        // Call the send action
        onSend()
        
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
        guard isEmpty else { return }
        
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            placeholderOpacity = 0.6
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

// MARK: - Preview

#Preview("Empty State") {
    ConciergeInputFieldPreviewContainer()
}

#Preview("Typing Short") {
    ConciergeInputFieldPreviewContainer(initialText: "Hi")
}

#Preview("Typing Long") {
    ConciergeInputFieldPreviewContainer(initialText: "Looking for anime like Attack on Titan")
}

#Preview("Import Intent") {
    ConciergeInputFieldPreviewContainer(
        initialText: "Naruto\nOne Piece\nBleach\nDeath Note"
    )
}

#Preview("Recommendation Intent") {
    ConciergeInputFieldPreviewContainer(
        initialText: "Can you recommend something with a good vibe?"
    )
}

// MARK: - Preview Container

private struct ConciergeInputFieldPreviewContainer: View {
    @State private var text: String
    @State private var detectedIntent: PrototypeConciergeIntent = .unknown
    
    init(initialText: String = "") {
        _text = State(initialValue: initialText)
    }
    
    var body: some View {
        ZStack {
            // Background gradient for glass effect visibility
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.3),
                    Color.blue.opacity(0.3),
                    Color.cyan.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // Show current intent for debugging
                if detectedIntent != .unknown {
                    Text("Detected: \(intentDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
                
                ConciergeInputField(
                    text: $text,
                    onSend: {
                        print("📤 Send: \(text)")
                    },
                    detectedIntent: $detectedIntent
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
    
    private var intentDescription: String {
        switch detectedIntent {
        case .unknown:
            return "Unknown"
        case .importList(let count):
            return "Import (\(count) items)"
        case .recommendation:
            return "Recommendation"
        }
    }
}

// MARK: - Usage Example

/*
 Example usage in a parent view:
 
 struct ConciergeChatView: View {
     @State private var inputText = ""
     @State private var currentIntent: PrototypeConciergeIntent = .unknown
     
     var body: some View {
         VStack {
             // Chat messages...
             
             ConciergeInputField(
                 text: $inputText,
                 onSend: {
                     sendMessage(inputText, intent: currentIntent)
                 },
                 detectedIntent: $currentIntent
             )
             .padding(.horizontal)
             .padding(.bottom)
         }
     }
     
     private func sendMessage(_ text: String, intent: PrototypeConciergeIntent) {
         // Handle message based on detected intent
         switch intent {
         case .importList(let count):
             print("Importing \(count) titles...")
         case .recommendation:
             print("Getting recommendations...")
         case .unknown:
             print("Processing general query...")
         }
     }
 }
 */

#endif
