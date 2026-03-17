// NOTE: Prototype-only implementation. Not shipped in release builds.
#if DEBUG
// MARK: - Experimental Concierge Prototype
// NOTE: Debug-only prototype UI and architecture sketch. Not used by the app unless explicitly wired.

import SwiftUI
import Combine
import UIKit

// MARK: - Dependency Injection Protocols

protocol HapticFeedbackProtocol {
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat)
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType)
}

protocol IntentDetectionProtocol {
    func detectIntent(from text: String) -> PrototypeConciergeIntentModel
}

protocol ImageLoadingProtocol {
    func loadImage(from url: URL) async throws -> UIImage
}

// MARK: - Production Implementations

final class ProductionHapticManager: HapticFeedbackProtocol {
    static let shared = ProductionHapticManager()
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    
    private var lastHapticTime: Date = .distantPast
    private let minimumHapticInterval: TimeInterval = 0.05 // Prevent spam
    
    private init() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()
    }
    
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) >= minimumHapticInterval else { return }
        lastHapticTime = now
        
        switch style {
        case .light:
            impactLight.impactOccurred(intensity: intensity)
        case .medium:
            impactMedium.impactOccurred(intensity: intensity)
        case .heavy:
            impactHeavy.impactOccurred(intensity: intensity)
        default:
            impactLight.impactOccurred(intensity: intensity)
        }
    }
    
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
    }
}

// MARK: - View Models (Separation of Concerns)

@MainActor
final class PrototypeConciergeViewModel: ObservableObject {
    @Published var messages: [PrototypeConciergeMessage] = []
    @Published var inputText: String = ""
    @Published var isWorking: Bool = false
    @Published var detectedIntent: PrototypeConciergeIntentModel = .unknown
    @Published var showDetectedChips: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let haptics: HapticFeedbackProtocol
    private let intentDetector: IntentDetectionProtocol

    init(
        haptics: HapticFeedbackProtocol = ProductionHapticManager.shared,
        intentDetector: IntentDetectionProtocol = ProductionIntentDetector()
    ) {
        self.haptics = haptics
        self.intentDetector = intentDetector
        setupBindings()
    }
    
    private func setupBindings() {
        $inputText
            .dropFirst()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                self?.analyzeInput(text)
            }
            .store(in: &cancellables)
    }
    
    private func analyzeInput(_ text: String) {
        let intent = intentDetector.detectIntent(from: text)
        
        if detectedIntent != intent {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                detectedIntent = intent
            }
            haptics.impact(.light, intensity: 0.3)
        }
        
        if case .importList(let count) = intent, count > 0 {
            showDetectedChips = true
        } else {
            showDetectedChips = false
        }
    }
    
    func sendMessage() {
        guard !inputText.isEmpty else { return }
        
        haptics.impact(.medium, intensity: 0.7)
        
        let message = PrototypeConciergeMessage(
            id: UUID(),
            role: .user,
            text: inputText,
            timestamp: Date()
        )
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            messages.append(message)
            inputText = ""
            detectedIntent = .unknown
            showDetectedChips = false
        }
        
        // Trigger processing
        processUserMessage(message)
    }
    
    private func processUserMessage(_ message: PrototypeConciergeMessage) {
        isWorking = true
        
        // Simulate async work
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            await MainActor.run {
                self?.isWorking = false
                self?.addAssistantResponse()
            }
        }
    }
    
    private func addAssistantResponse() {
        let response = PrototypeConciergeMessage(
            id: UUID(),
            role: .assistant,
            text: "Here are some recommendations for you:",
            timestamp: Date()
        )
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            messages.append(response)
        }
    }
}

// MARK: - Models

struct PrototypeConciergeMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let text: String
    let timestamp: Date
    
    enum MessageRole {
        case user
        case assistant
    }
}

enum PrototypeConciergeIntentModel: Equatable {
    case unknown
    case importList(count: Int)
    case recommendation
}

struct ProductionIntentDetector: IntentDetectionProtocol {
    func detectIntent(from text: String) -> PrototypeConciergeIntentModel {
        let lowercased = text.lowercased()
        
        // Check for list indicators
        let hasNewlines = text.contains("\n")
        let hasCommas = text.split(separator: ",").count > 1
        let hasEpisodeMarkers = lowercased.contains("ep") || lowercased.contains("episode")
        let hasStatusWords = lowercased.contains("watching") || lowercased.contains("completed") || lowercased.contains("dropped")
        
        if hasNewlines || (hasCommas && text.count > 20) || hasEpisodeMarkers || hasStatusWords {
            let titles = text.split(whereSeparator: { $0 == "\n" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count > 2 }
            return .importList(count: titles.count)
        }
        
        // Check for recommendation keywords
        let recommendationKeywords = ["recommend", "suggest", "something", "vibe", "like", "similar", "funny", "sad", "action"]
        if recommendationKeywords.contains(where: { lowercased.contains($0) }) {
            return .recommendation
        }
        
        return .unknown
    }
}

// MARK: - Views

struct PrototypeConciergeMagicalView: View {
    @StateObject private var viewModel = PrototypeConciergeViewModel()
    @Namespace private var animationNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        VStack(spacing: 0) {
            messageScrollView
            inputSection
        }
        .background(Color(.systemBackground))
    }
    
    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    if viewModel.messages.isEmpty {
                        emptyStateView
                    }
                    
                    ForEach(viewModel.messages) { message in
                        PrototypeMessageBubble(
                            message: message,
                            viewModel: viewModel,
                            namespace: animationNamespace
                        )
                        .id(message.id)
                    }
                    
                    if viewModel.isWorking {
                        PrototypeThinkingBubble()
                            .id("thinking")
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isWorking) { _, isWorking in
                if isWorking {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            MascotWelcomeView()
                .frame(height: 120)
            
            VStack(spacing: 12) {
                Text("Good \(timeOfDay)")
                    .font(.system(size: 28, weight: .light, design: .serif))
                
                Text("Ready to track something?")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    private var timeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default: return "night"
        }
    }
    
    private var inputSection: some View {
        VStack(spacing: 8) {
            if viewModel.showDetectedChips {
                DetectedChipsView(intent: viewModel.detectedIntent)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            PrototypeMagicalInputField(
                text: $viewModel.inputText,
                intent: viewModel.detectedIntent,
                onSend: { viewModel.sendMessage() }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Message Bubble

struct PrototypeMessageBubble: View {
    let message: PrototypeConciergeMessage
    @ObservedObject var viewModel: PrototypeConciergeViewModel
    var namespace: Namespace.ID
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
                userBubble
            } else {
                assistantBubble
                Spacer(minLength: 40)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
    
    private var accessibilityLabel: String {
        switch message.role {
        case .user:
            return "You said: \(message.text)"
        case .assistant:
            return "Concierge said: \(message.text)"
        }
    }
    
    private var userBubble: some View {
        Text(message.text)
            .font(.system(size: dynamicTypeSize >= .xxLarge ? 18 : 15))
            .lineSpacing(4)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .frame(maxWidth: min(UIScreen.main.bounds.width * 0.75, 300), alignment: .trailing)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private var assistantBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            MascotAvatar(size: 32)
            
            Text(message.text)
                .font(.system(size: dynamicTypeSize >= .xxLarge ? 18 : 15))
                .lineSpacing(4)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.6),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )
                )
                .frame(maxWidth: min(UIScreen.main.bounds.width * 0.75, 300), alignment: .leading)
        }
    }
}

// MARK: - Thinking Bubble

struct PrototypeThinkingBubble: View {
    @State private var phase = 0
    @State private var phaseTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            MascotAvatar(size: 32, isThinking: true)
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.primary.opacity(phase == index ? 0.6 : 0.2))
                            .frame(width: 6, height: 6)
                            .scaleEffect(phase == index && !reduceMotion ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: phase)
                    }
                }
                
                Text("Thinking...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .onAppear {
            phaseTask?.cancel()
            phaseTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    phase = (phase + 1) % 3
                }
            }
        }
        .onDisappear {
            phaseTask?.cancel()
            phaseTask = nil
        }
        .accessibilityLabel("Concierge is thinking")
    }
}

// MARK: - Magical Input Field

struct PrototypeMagicalInputField: View {
    @Binding var text: String
    let intent: PrototypeConciergeIntentModel
    let onSend: () -> Void
    
    @FocusState private var isFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private var placeholderOpacity: Double {
        isFocused ? 0.5 : 0.3
    }
    
    private var textWeight: Font.Weight {
        text.count < 3 ? .light : .regular
    }
    
    var body: some View {
        HStack(spacing: 12) {
            textField
            sendButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            isFocused ? 
                                Color.accentColor.opacity(0.3) :
                                Color.white.opacity(0.3),
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                )
                .shadow(
                    color: isFocused ? .accentColor.opacity(0.1) : .clear,
                    radius: isFocused ? 8 : 0,
                    x: 0,
                    y: isFocused ? 2 : 0
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
    
    private var textField: some View {
        TextField("", text: $text, axis: .vertical)
            .font(.system(size: dynamicTypeSize >= .xxLarge ? 18 : 15, weight: textWeight))
            .lineLimit(1...4)
            .focused($isFocused)
            .overlay(alignment: .leading) {
                if text.isEmpty {
                    Text("Start typing, paste, or ask...")
                        .font(.system(size: dynamicTypeSize >= .xxLarge ? 18 : 15, weight: .light))
                        .foregroundColor(.secondary.opacity(placeholderOpacity))
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: placeholderOpacity)
                }
            }
    }
    
    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .scaleEffect(text.isEmpty ? 0.9 : 1.0)
        }
        .disabled(text.isEmpty)
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2), value: text.isEmpty)
    }
}

// MARK: - Detected Chips

struct DetectedChipsView: View {
    let intent: PrototypeConciergeIntentModel
    
    var body: some View {
        HStack(spacing: 8) {
            switch intent {
            case .importList(let count):
                chip(icon: "doc.text", text: "\(count) titles detected", color: .blue)
            case .recommendation:
                chip(icon: "sparkles", text: "Recommendation request", color: .purple)
            case .unknown:
                EmptyView()
            }
        }
        .padding(.horizontal, 4)
    }
    
    private func chip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Mascot Views

struct MascotWelcomeView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 100, height: 100)
            
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 44))
                .foregroundStyle(.primary)
                .rotationEffect(.degrees(isAnimating && !reduceMotion ? 5 : 0))
                .scaleEffect(isAnimating && !reduceMotion ? 1.05 : 1.0)
                .animation(
                    .easeInOut(duration: 4).repeatForever(autoreverses: true),
                    value: isAnimating
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct MascotAvatar: View {
    let size: CGFloat
    var isThinking: Bool = false
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
            
            Image(systemName: "moon.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.primary)
                .offset(y: isThinking && !reduceMotion ? -3 : 0)
                .animation(
                    isThinking && !reduceMotion ? 
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true) :
                        .default,
                    value: isThinking
                )
        }
        .accessibilityLabel("Kuro mascot")
    }
}

// MARK: - Preview

#Preview("Concierge Magical View") {
    PrototypeConciergeMagicalView()
}

#Preview("Empty State") {
    PrototypeConciergeMagicalView()
        .onAppear {
            // Force empty state
        }
}

#Preview("With Messages") {
    let view = PrototypeConciergeMagicalView()
    // Add mock messages
    return view
}

#endif
