#if DEBUG
// ConciergeMessageBubbles.swift
// Kuro iOS App - Concierge Chat Interface
// iOS 26+ | SwiftUI Message Bubbles

import SwiftUI

// MARK: - Thinking Stage Enum

enum ThinkingStage: String, CaseIterable {
    case reading = "Reading your list..."
    case finding = "Finding matches..."
    case comparing = "Comparing with your collection..."
    case almostReady = "Almost ready..."
    
    var progress: Double {
        switch self {
        case .reading: return 0.25
        case .finding: return 0.50
        case .comparing: return 0.75
        case .almostReady: return 0.95
        }
    }
    
    var hapticIntensity: Double {
        switch self {
        case .reading: return 0.3
        case .finding: return 0.5
        case .comparing: return 0.7
        case .almostReady: return 0.9
        }
    }
}

// MARK: - User Message Bubble

struct UserMessageBubble: View {
    let text: String
    let isSending: Bool
    
    @State private var isAppearing: Bool = false
    
    // MARK: - Constants
    private enum Constants {
        static let maxWidthRatio: CGFloat = 0.75
        static let fontSize: CGFloat = 15
        static let letterSpacing: CGFloat = -0.01
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 12
        static let baseCornerRadius: CGFloat = 20
        static let speechCornerRadius: CGFloat = 4
        static let backgroundOpacity: Double = 0.88
        static let animationDuration: Double = 0.35
        static let springResponse: Double = 0.5
        static let springDamping: Double = 0.8
    }
    
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            
            Text(text)
                .font(.system(size: Constants.fontSize, weight: .regular, design: .default))
                .kerning(Constants.letterSpacing)
                .foregroundColor(.white)
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.vertical, Constants.verticalPadding)
                .background(
                    BubbleShape()
                        .fill(Color.black.opacity(Constants.backgroundOpacity))
                )
                .overlay(
                    Group {
                        if isSending {
                            SendingIndicator()
                                .transition(.opacity)
                        }
                    }
                )
                .frame(maxWidth: UIScreen.main.bounds.width * Constants.maxWidthRatio, alignment: .trailing)
                .offset(y: isAppearing ? 0 : 20)
                .opacity(isAppearing ? 1 : 0)
                .scaleEffect(isAppearing ? 1 : 0.95)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onAppear {
            withAnimation(
                .spring(
                    response: Constants.springResponse,
                    dampingFraction: Constants.springDamping
                )
            ) {
                isAppearing = true
            }
        }
    }
}

// MARK: - Assistant Message Bubble

struct AssistantMessageBubble: View {
    let text: String
    let isThinking: Bool
    let thinkingStage: ThinkingStage?
    
    @State private var isAppearing: Bool = false
    @State private var glowOpacity: Double = 0.3
    
    // MARK: - Constants
    private enum Constants {
        static let maxWidthRatio: CGFloat = 0.80
        static let fontSize: CGFloat = 15
        static let lineHeight: CGFloat = 1.5
        static let cornerRadius: CGFloat = 20
        static let borderWidth: CGFloat = 1
        static let shadowRadius: CGFloat = 12
        static let shadowYOffset: CGFloat = 4
        static let shadowOpacity: Double = 0.06
        static let innerGlowHeight: CGFloat = 1
        static let innerGlowOpacity: Double = 0.5
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 14
        static let animationDuration: Double = 0.35
        static let springResponse: Double = 0.5
        static let springDamping: Double = 0.8
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Mascot avatar
            MascotAvatarView(isThinking: isThinking)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 8) {
                if isThinking {
                    ThinkingIndicator(stage: thinkingStage)
                        .transition(.opacity.combined(with: .scale))
                } else {
                    Text(text)
                        .font(.system(size: Constants.fontSize, weight: .regular, design: .default))
                        .lineSpacing(Constants.lineHeight * Constants.fontSize - Constants.fontSize)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .background(
                ZStack {
                    // Base glass material
                    RoundedRectangle(cornerRadius: Constants.cornerRadius)
                        .fill(.ultraThinMaterial)
                    
                    // Gradient border overlay
                    RoundedRectangle(cornerRadius: Constants.cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.60),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: Constants.borderWidth
                        )
                    
                    // Inner glow at top edge
                    VStack {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(Constants.innerGlowOpacity),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: Constants.innerGlowHeight)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                }
            )
            .shadow(
                color: Color.black.opacity(Constants.shadowOpacity),
                radius: Constants.shadowRadius,
                x: 0,
                y: Constants.shadowYOffset
            )
            .frame(maxWidth: UIScreen.main.bounds.width * Constants.maxWidthRatio, alignment: .leading)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .offset(y: isAppearing ? 0 : 15)
        .opacity(isAppearing ? 1 : 0)
        .onAppear {
            withAnimation(
                .spring(
                    response: Constants.springResponse,
                    dampingFraction: Constants.springDamping
                )
            ) {
                isAppearing = true
            }
        }
        .onChange(of: isThinking) { _, newValue in
            if newValue {
                startGlowAnimation()
            }
        }
    }
    
    private func startGlowAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowOpacity = 0.6
        }
    }
}

// MARK: - Custom Bubble Shape (Speech Bubble)

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 20
        let speechCornerRadius: CGFloat = 4
        
        var path = Path()
        
        // Start from top-left
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        
        // Top edge to top-right
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        
        // Right edge - speech bubble tail area
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius - speechCornerRadius))
        
        // Speech bubble tail (subtle curve)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - speechCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX + 4, y: rect.maxY - 4)
        )
        
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        
        // Left edge to close
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Thinking Indicator

private struct ThinkingIndicator: View {
    let stage: ThinkingStage?
    
    @State private var animateDots: Bool = false
    @State private var progress: Double = 0
    
    private let dotSize: CGFloat = 8
    private let dotSpacing: CGFloat = 4
    private let animationDuration: Double = 0.5
    private let dotLift: CGFloat = 6
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Stage text with typing dots
            HStack(spacing: 8) {
                Text(stage?.rawValue ?? "Thinking...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: dotSpacing) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.primary.opacity(0.6))
                            .frame(width: dotSize, height: dotSize)
                            .offset(y: animateDots ? -dotLift : 0)
                            .animation(
                                .easeInOut(duration: animationDuration)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                                value: animateDots
                            )
                    }
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 2)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 2)
                }
            }
            .frame(height: 2)
            .animation(.easeInOut(duration: 0.3), value: progress)
        }
        .onAppear {
            animateDots = true
            updateProgress()
        }
        .onChange(of: stage) { _, _ in
            updateProgress()
            triggerHaptic()
        }
    }
    
    private func updateProgress() {
        withAnimation(.easeInOut(duration: 0.5)) {
            progress = stage?.progress ?? 0
        }
    }
    
    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: CGFloat(stage?.hapticIntensity ?? 0.5))
    }
}

// MARK: - Sending Indicator

private struct SendingIndicator: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
        }
        .clipShape(BubbleShape())
    }
}

// MARK: - Mascot Avatar View

private struct MascotAvatarView: View {
    let isThinking: Bool
    
    @State private var bounceOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1
    
    var body: some View {
        ZStack {
            // Placeholder mascot circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Mascot face placeholder
                    VStack(spacing: 2) {
                        // Eyes
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: isThinking ? 3 : 4, height: isThinking ? 3 : 4)
                            Circle()
                                .fill(Color.white)
                                .frame(width: isThinking ? 3 : 4, height: isThinking ? 3 : 4)
                        }
                        // Mouth
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white)
                            .frame(width: isThinking ? 4 : 6, height: 2)
                    }
                )
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .offset(y: bounceOffset)
        }
        .onAppear {
            if isThinking {
                startThinkingAnimation()
            }
        }
        .onChange(of: isThinking) { _, newValue in
            if newValue {
                startThinkingAnimation()
            } else {
                stopThinkingAnimation()
            }
        }
    }
    
    private func startThinkingAnimation() {
        // Bounce animation
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            bounceOffset = -3
        }
        
        // Subtle rotation
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            rotation = 5
        }
        
        // Breathing scale
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            scale = 1.05
        }
    }
    
    private func stopThinkingAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            bounceOffset = 0
            rotation = 0
            scale = 1
        }
    }
}

// MARK: - Preview

#Preview("User Messages") {
    ScrollView {
        VStack(spacing: 16) {
            UserMessageBubble(
                text: "Hey, can you recommend some anime like Attack on Titan?",
                isSending: false
            )
            
            UserMessageBubble(
                text: "I really enjoyed the dark fantasy elements and the plot twists.",
                isSending: false
            )
            
            UserMessageBubble(
                text: "Short message.",
                isSending: true
            )
            
            UserMessageBubble(
                text: "This is a very long message that should demonstrate the max width behavior of the user message bubble in the Concierge chat interface.",
                isSending: false
            )
        }
        .padding(.vertical)
    }
    .background(Color.gray.opacity(0.1))
}

#Preview("Assistant Messages") {
    ScrollView {
        VStack(spacing: 16) {
            AssistantMessageBubble(
                text: "Based on your love for dark fantasy, I'd recommend checking out 'Demon Slayer' and 'Jujutsu Kaisen'. Both have intense action and compelling storylines!",
                isThinking: false,
                thinkingStage: nil
            )
            
            AssistantMessageBubble(
                text: "If you're looking for something with similar political intrigue, 'Code Geass' might be perfect for you.",
                isThinking: false,
                thinkingStage: nil
            )
            
            // Thinking states
            ForEach(ThinkingStage.allCases, id: \.self) { stage in
                AssistantMessageBubble(
                    text: "",
                    isThinking: true,
                    thinkingStage: stage
                )
            }
        }
        .padding(.vertical)
    }
    .background(
        LinearGradient(
            colors: [.purple.opacity(0.1), .blue.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    )
}

#Preview("Combined Chat") {
    ScrollView {
        VStack(spacing: 16) {
            // User asks
            UserMessageBubble(
                text: "What should I watch next?",
                isSending: false
            )
            
            // Assistant responds
            AssistantMessageBubble(
                text: "Let me analyze your watch history to find the perfect recommendation!",
                isThinking: false,
                thinkingStage: nil
            )
            
            // Assistant thinking
            AssistantMessageBubble(
                text: "",
                isThinking: true,
                thinkingStage: .finding
            )
            
            // Assistant final response
            AssistantMessageBubble(
                text: "Based on your recent watches, I highly recommend 'Chainsaw Man'! It matches your preference for dark, action-packed series with complex characters.",
                isThinking: false,
                thinkingStage: nil
            )
            
            // User replies
            UserMessageBubble(
                text: "Thanks! I'll add it to my list.",
                isSending: false
            )
        }
        .padding(.vertical)
    }
    .background(Color(.systemBackground))
}

#Preview("Dark Mode") {
    ScrollView {
        VStack(spacing: 16) {
            UserMessageBubble(
                text: "How's my manga collection looking?",
                isSending: false
            )
            
            AssistantMessageBubble(
                text: "You've got 47 manga in your collection! Your most-read genre is seinen, followed by shonen.",
                isThinking: false,
                thinkingStage: nil
            )
        }
        .padding(.vertical)
    }
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}

#endif
