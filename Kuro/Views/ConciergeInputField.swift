// MARK: - ConciergeInputField.swift
// Concierge input field with intent detection and paste cues.
// Designed to be lightweight: no per-keystroke haptics, minimal animations.
// The intent and paste rules (`ConciergeIntentDetector`, `PrototypeConciergeIntent`) live in
// Kuro/Concierge/ConciergeRouting.swift.

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

// MARK: - Main Input Field View

/// The magical Concierge input field with dynamic behaviors
struct ConciergeInputField: View {

    // MARK: - Environment

    @Environment(NetworkMonitor.self) private var networkMonitor

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
    @State private var isInputFocused: Bool = false
    @State private var showDetectedChip = false
    @State private var detectedCount = 0
    @State private var lastTextLength = 0
    @State private var suggestions: [ConciergeSuggestion] = []
    @State private var suggestionTask: Task<Void, Never>? = nil
    @State private var detectedChipTask: Task<Void, Never>? = nil
    @State private var measuredTextHeight: CGFloat = 20
    @State private var lastAutoSentTextFingerprint: Int? = nil
    // Keep suggestion generation off until the bar is reintroduced in this prototype path.
    private let showsSuggestionBar = false
    
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
        !isEmpty && !isSending && networkMonitor.isConnected
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
                .accessibilityIdentifier("concierge_text_input")
                .frame(height: min(inputMaxHeight, max(Constants.lineHeight, measuredTextHeight)))
                .onChange(of: text) { oldValue, newValue in
                    handleTextChange(from: oldValue, to: newValue)
                }
            }

            sendButton
        }
        .padding(.vertical, 6)
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
        Text(networkMonitor.isConnected ? "Ask Whisper..." : "Offline")
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
        .accessibilityLabel("Send message")
        .accessibilityHint(!networkMonitor.isConnected ? "You're offline" : canSend ? "Sends your message to Concierge" : "Type a message first")
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
        let wasPaste = ConciergeIntentDetector.isPaste(previousLength: lastTextLength, newText: newValue)

        // Handle list detection chip
        handleListDetection(intent: newIntent, wasPaste: wasPaste)
        maybeAutoSend(intent: newIntent, wasPaste: wasPaste, text: newValue)

        lastTextLength = newValue.count

        updateSuggestionsDebounced(newValue)
    }

    private func maybeAutoSend(intent: PrototypeConciergeIntent, wasPaste: Bool, text: String) {
        guard !isSending else { return }
        guard let onAutoSend else { return }

        // Only a paste the detector is confident is an import list (ConciergeIntentDetector.autoSend).
        guard let send = ConciergeIntentDetector.autoSend(for: text, intent: intent, wasPaste: wasPaste) else { return }

        // Prevent double-firing for the same pasted payload.
        if lastAutoSentTextFingerprint == send.fingerprint { return }
        lastAutoSentTextFingerprint = send.fingerprint

        onAutoSend(send.text)
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
        guard showsSuggestionBar else { return }
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
        }

        Task { @MainActor in
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
