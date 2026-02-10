#if DEBUG
import SwiftUI

// MARK: - Color Extensions

/// Dark Mode color definitions for the Kuro Concierge
/// These colors are designed to maintain the "Editorial Minimalism" aesthetic
/// while providing proper contrast and visual hierarchy in dark mode.
extension Color {
    /// Base glass fill for dark mode cards (subtle white presence)
    static let glassDark = Color.white.opacity(0.05)
    
    /// Border color for dark mode glass cards (subtle definition)
    static let glassDarkBorder = Color.white.opacity(0.15)
    
    /// Accent glow for dark mode focus states and highlights
    static let accentGlowDark = Color.purple.opacity(0.2)
    
    /// User bubble base color in dark mode (purple tint instead of heavy black)
    static let userBubbleDark = Color.purple.opacity(0.30)
    
    /// Subtle gradient overlay for user bubble top edge
    static let userBubbleGradientTop = Color.white.opacity(0.10)
    
    /// Input field background in dark mode
    static let inputFieldDark = Color.white.opacity(0.05)
    
    /// Input field border when not focused (subtle presence)
    static let inputFieldBorderDark = Color.white.opacity(0.10)
}

// MARK: - Adaptive Glass Card

/// A view modifier that creates an adaptive glass card
/// Automatically adjusts appearance based on the current color scheme
/// 
/// Design Rationale:
/// - Light mode uses `ultraThinMaterial` for that signature iOS glass look
/// - Dark mode uses a subtle white fill with inner glow to maintain depth
/// without the harshness of pure black cards
struct AdaptiveGlassCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(backgroundView)
            .overlay(borderOverlay)
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }
    
    // MARK: Background
    
    @ViewBuilder
    private var backgroundView: some View {
        if colorScheme == .dark {
            // Dark mode: White 5% fill with subtle inner glow
            ZStack {
                // Base fill
                Color.glassDark
                
                // Inner glow at top (subtle purple/white gradient)
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        } else {
            // Light mode: Standard ultra-thin material
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
    
    // MARK: Border
    
    @ViewBuilder
    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: borderColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
    
    private var borderColors: [Color] {
        if colorScheme == .dark {
            // Dark mode: 25% → 5% white gradient (subtle but present)
            return [
                Color.white.opacity(0.25),
                Color.white.opacity(0.05)
            ]
        } else {
            // Light mode: 72% → 18% white gradient (classic glass border)
            return [
                Color.white.opacity(0.72),
                Color.white.opacity(0.18)
            ]
        }
    }
    
    // MARK: Shadow
    
    private var shadowColor: Color {
        if colorScheme == .dark {
            // Dark mode: Deeper shadow for depth (50% black)
            return Color.black.opacity(0.50)
        } else {
            // Light mode: Subtle shadow (8% black)
            return Color.black.opacity(0.08)
        }
    }
    
    private var shadowRadius: CGFloat {
        colorScheme == .dark ? 20 : 12
    }
    
    private var shadowY: CGFloat {
        colorScheme == .dark ? 8 : 4
    }
}

// MARK: - View Extension

extension View {
    /// Applies the adaptive glass card styling
    /// Automatically handles light/dark mode transitions
    func adaptiveGlassCard() -> some View {
        modifier(AdaptiveGlassCard())
    }
}

// MARK: - Dark Mode Message Bubble

/// Enum defining the two types of message bubbles in the concierge
enum MessageBubbleType {
    case user      // Sent by the user
    case assistant // Sent by the AI assistant
}

/// A reusable message bubble component with full dark mode support
/// 
/// Design Philosophy:
/// - User bubbles use a purple tint base instead of heavy black (88%)
///   to maintain warmth and brand identity in dark mode
/// - Assistant bubbles use the adaptive glass card for consistency
///   with the rest of the app's UI
struct DarkModeMessageBubble: View {
    let type: MessageBubbleType
    let text: String
    let timestamp: Date?
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        type: MessageBubbleType,
        text: String,
        timestamp: Date? = nil
    ) {
        self.type = type
        self.text = text
        self.timestamp = timestamp
    }
    
    var body: some View {
        HStack {
            if type == .user {
                Spacer(minLength: 40)
            }
            
            VStack(alignment: type == .user ? .trailing : .leading, spacing: 4) {
                bubbleContent
                
                if let timestamp = timestamp {
                    Text(timestampFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            
            if type == .assistant {
                Spacer(minLength: 40)
            }
        }
    }
    
    // MARK: Bubble Content
    
    @ViewBuilder
    private var bubbleContent: some View {
        switch type {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        }
    }
    
    // MARK: User Bubble
    
    private var userBubble: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(userBubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    @ViewBuilder
    private var userBubbleBackground: some View {
        if colorScheme == .dark {
            // Dark mode: Purple 30% base with white gradient overlay
            ZStack {
                // Base purple tint
                Color.userBubbleDark
                
                // Top gradient overlay for depth
                LinearGradient(
                    colors: [
                        Color.userBubbleGradientTop,
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // Subtle white border
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        } else {
            // Light mode: Standard purple/black styling
            Color.black.opacity(0.88)
        }
    }
    
    // MARK: Assistant Bubble
    
    private var assistantBubble: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .adaptiveGlassCard()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    // MARK: Helpers
    
    private var timestampFormatted: String {
        guard let timestamp = timestamp else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Dark Mode Input Field

/// An adaptive input field with elegant dark mode styling
/// 
/// Key Features:
/// - Focus state with purple glow (instead of accent color)
/// - Subtle white border when not focused
/// - Purple tinted send button when enabled
struct DarkModeInputField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onSend: () -> Void
    var placeholder: String = "Message..."
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Text input area
            textField
            
            // Send button
            sendButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(inputBackground)
        .overlay(inputBorder)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
    
    // MARK: Text Field
    
    private var textField: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(.body)
            .foregroundStyle(.primary)
            .lineLimit(1...5)
            .tint(colorScheme == .dark ? .purple : .accentColor)
    }
    
    // MARK: Send Button
    
    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(sendButtonColor)
                .background(
                    Circle()
                        .fill(colorScheme == .dark ? Color.purple.opacity(0.2) : Color.clear)
                        .scaleEffect(1.2)
                )
        }
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .buttonStyle(.plain)
    }
    
    private var sendButtonColor: Color {
        let isEnabled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if colorScheme == .dark {
            // Dark mode: Purple tint when enabled, muted when disabled
            return isEnabled ? .purple.opacity(0.9) : .gray.opacity(0.4)
        } else {
            // Light mode: Standard accent color
            return isEnabled ? .accentColor : .gray.opacity(0.4)
        }
    }
    
    // MARK: Background
    
    @ViewBuilder
    private var inputBackground: some View {
        if colorScheme == .dark {
            // Dark mode: White 5% opacity with subtle inner glow when focused
            ZStack {
                Color.inputFieldDark
                
                if isFocused {
                    // Purple focus glow
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.accentGlowDark, lineWidth: 1)
                        .blur(radius: 4)
                }
            }
        } else {
            // Light mode: Standard material
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
    
    // MARK: Border
    
    @ViewBuilder
    private var inputBorder: some View {
        if colorScheme == .dark {
            // Dark mode: Subtle white 10% when not focused, purple when focused
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.purple.opacity(0.3) : Color.inputFieldBorderDark,
                    lineWidth: isFocused ? 1.5 : 0.5
                )
        } else {
            // Light mode: Standard glass border
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
        }
    }
}

// MARK: - Message Model

/// Data model for concierge messages
struct PrototypeConciergeDarkMessage: Identifiable, Equatable {
    let id = UUID()
    let type: MessageBubbleType
    let text: String
    let timestamp: Date
    
    static func user(_ text: String) -> PrototypeConciergeDarkMessage {
        PrototypeConciergeDarkMessage(type: .user, text: text, timestamp: Date())
    }
    
    static func assistant(_ text: String) -> PrototypeConciergeDarkMessage {
        PrototypeConciergeDarkMessage(type: .assistant, text: text, timestamp: Date())
    }
}

// MARK: - Adaptive Concierge View

/// The complete adaptive concierge view with full dark mode support
/// 
/// This view combines all dark mode components into a cohesive interface
/// that automatically adapts to the system's color scheme.
struct AdaptiveConciergeView: View {
    // MARK: State
    
    @State private var messages: [PrototypeConciergeDarkMessage] = []
    @State private var inputText: String = ""
    @State private var isInputFocused: Bool = false
    @State private var isTyping: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: Configuration
    
    var title: String = "Concierge"
    var subtitle: String? = "Your personal anime & manga assistant"
    
    // MARK: Body
    
    var body: some View {
        ZStack {
            // Background
            background
            
            // Main content
            VStack(spacing: 0) {
                // Navigation header
                header
                
                // Messages list
                messagesList
                
                // Input area
                inputArea
            }
        }
        .onAppear(perform: loadWelcomeMessage)
    }
    
    // MARK: Background
    
    @ViewBuilder
    private var background: some View {
        if colorScheme == .dark {
            // Dark mode: Deep background with subtle gradient
            Color.black
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.05),
                            Color.clear,
                            Color.clear,
                            Color.blue.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()
        } else {
            // Light mode: System background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
    }
    
    // MARK: Header
    
    private var header: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .adaptiveGlassCard()
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: Messages List
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        DarkModeMessageBubble(
                            type: message.type,
                            text: message.text,
                            timestamp: message.timestamp
                        )
                        .id(message.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: message.type == .user ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    
                    if isTyping {
                        typingIndicator
                            .id("typing")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isTyping) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private var typingIndicator: some View {
        HStack {
            Spacer(minLength: 40)
            
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .offset(y: isTyping ? -4 : 0)
                        .animation(
                            .easeInOut(duration: 0.4)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: isTyping
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .adaptiveGlassCard()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
    
    // MARK: Input Area
    
    private var inputArea: some View {
        DarkModeInputField(
            text: $inputText,
            isFocused: $isInputFocused,
            onSend: sendMessage,
            placeholder: "Ask about anime or manga..."
        )
        .padding()
        .background(
            colorScheme == .dark
                ? Color.black.opacity(0.8).ignoresSafeArea(edges: .bottom)
                : Color.clear.ignoresSafeArea(edges: .bottom)
        )
    }
    
    // MARK: Actions
    
    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Add user message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            messages.append(.user(trimmedText))
            inputText = ""
        }
        
        // Simulate assistant response
        isTyping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isTyping = false
                messages.append(.assistant("I'd be happy to help you find anime and manga recommendations! What genres are you interested in?"))
            }
        }
    }
    
    private func loadWelcomeMessage() {
        guard messages.isEmpty else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                messages.append(.assistant("Welcome to Kuro Concierge! 🌸\n\nI'm here to help you discover your next favorite anime or manga. Just let me know what you're in the mood for!"))
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
        if isTyping {
            withAnimation {
                proxy.scrollTo("typing", anchor: .bottom)
            }
        }
    }
}

// MARK: - Preview

#Preview("Light & Dark Mode") {
    HStack(spacing: 0) {
        // Light mode preview
        AdaptiveConciergeView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(.light)
        
        Divider()
        
        // Dark mode preview
        AdaptiveConciergeView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(.dark)
    }
}

#Preview("Components - Light Mode") {
    ScrollView {
        VStack(spacing: 24) {
            Group {
                Text("User Bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                DarkModeMessageBubble(
                    type: .user,
                    text: "Can you recommend some good action anime?"
                )
                
                Text("Assistant Bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                DarkModeMessageBubble(
                    type: .assistant,
                    text: "I'd recommend checking out 'Demon Slayer' or 'Jujutsu Kaisen' for great action animation!"
                )
                
                Text("Input Field")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                DarkModeInputField(
                    text: .constant("Sample message..."),
                    isFocused: .constant(false),
                    onSend: {}
                )
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
    .preferredColorScheme(.light)
}

#Preview("Components - Dark Mode") {
    ScrollView {
        VStack(spacing: 24) {
            Group {
                Text("User Bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                DarkModeMessageBubble(
                    type: .user,
                    text: "Can you recommend some good action anime?"
                )
                
                Text("Assistant Bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                DarkModeMessageBubble(
                    type: .assistant,
                    text: "I'd recommend checking out 'Demon Slayer' or 'Jujutsu Kaisen' for great action animation!"
                )
                
                Text("Input Field")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                DarkModeInputField(
                    text: .constant("Sample message..."),
                    isFocused: .constant(false),
                    onSend: {}
                )
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
    .preferredColorScheme(.dark)
    .background(Color.black.ignoresSafeArea())
}

#endif
