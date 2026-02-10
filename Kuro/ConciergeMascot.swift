#if DEBUG
import SwiftUI

// MARK: - Mascot State

/// Represents the emotional/functional state of the Kuro mascot
enum MascotState: Equatable {
    case idle
    case listening
    case thinking
    case celebrating
    case concerned
    
    var accessibilityLabel: String {
        switch self {
        case .idle: return "Kuro is ready to help"
        case .listening: return "Kuro is listening"
        case .thinking: return "Kuro is thinking"
        case .celebrating: return "Kuro is celebrating"
        case .concerned: return "Kuro is concerned"
        }
    }
}

// MARK: - Haptic Feedback Helpers

/// Lightweight haptic feedback generator for micro-interactions
enum HapticStyle {
    case light
    case medium
    case heavy
    case success
    case warning
    case error
    case click  // Custom pattern for send action
    
    func trigger() {
        switch self {
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        case .click:
            // Custom click pattern - light double tap feel
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 0.7)
        }
    }
}

// MARK: - Micro-Interaction Modifiers

/// Provides consistent micro-interaction animations for tappable elements
struct MicroInteractionModifier: ViewModifier {
    let scale: CGFloat
    let hapticStyle: HapticStyle
    let animationDuration: Double
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(.easeOut(duration: animationDuration), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            hapticStyle.trigger()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onTap()
                    }
            )
    }
}

/// Modifier for card selection with scale and border stroke
struct CardSelectionModifier: ViewModifier {
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : isSelected ? 1.02 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: isSelected ? 2 : 0
                    )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            HapticStyle.light.trigger()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onTap()
                    }
            )
    }
}

/// Modifier for input focus with glow shadow
struct InputFocusModifier: ViewModifier {
    let isFocused: Bool
    let glowColor: Color
    let maxBlur: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(
                color: glowColor.opacity(isFocused ? 0.2 : 0),
                radius: isFocused ? maxBlur : 0,
                x: 0,
                y: isFocused ? 2 : 0
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Draggable Modifier with Bounds

/// Draggable modifier that keeps the view within screen bounds
struct BoundedDraggableModifier: ViewModifier {
    @Binding var offset: CGSize
    let bounds: CGRect
    let onDragEnd: ((CGSize) -> Void)?
    
    @State private var dragOffset: CGSize = .zero
    @GestureState private var isDragging = false
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
            .gesture(
                DragGesture()
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        let proposedOffset = CGSize(
                            width: offset.width + value.translation.width,
                            height: offset.height + value.translation.height
                        )
                        
                        // Apply bounds constraints
                        dragOffset = CGSize(
                            width: clamp(proposedOffset.width, min: bounds.minX, max: bounds.maxX) - offset.width,
                            height: clamp(proposedOffset.height, min: bounds.minY, max: bounds.maxY) - offset.height
                        )
                    }
                    .onEnded { value in
                        let newOffset = CGSize(
                            width: clamp(offset.width + value.translation.width, min: bounds.minX, max: bounds.maxX),
                            height: clamp(offset.height + value.translation.height, min: bounds.minY, max: bounds.maxY)
                        )
                        
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            offset = newOffset
                            dragOffset = .zero
                        }
                        
                        onDragEnd?(newOffset)
                    }
            )
    }
    
    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}

// MARK: - Mascot Face Component

/// The animated Kuro mascot face with all state animations
struct KuroMascotFace: View {
    let state: MascotState
    let size: CGFloat
    
    @State private var blinkPhase = false
    @State private var wavePhase = false
    @State private var idleTimer: Timer?
    
    var body: some View {
        ZStack {
            // Face shape
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.15, blue: 0.18),
                            Color(red: 0.08, green: 0.08, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            
            // Eyes
            HStack(spacing: size * 0.25) {
                eye
                eye
            }
            
            // Expression overlay based on state
            stateOverlay
        }
        .frame(width: size, height: size)
        .applyStateAnimation(state: state, size: size)
        .onAppear {
            startIdleAnimations()
        }
        .onDisappear {
            idleTimer?.invalidate()
        }
        .onChange(of: state) { _ in
            handleStateChange()
        }
    }
    
    @ViewBuilder
    private var eye: some View {
        RoundedRectangle(cornerRadius: blinkPhase ? size * 0.02 : size * 0.08)
            .fill(Color.white)
            .frame(width: size * 0.18, height: blinkPhase ? size * 0.02 : size * 0.18)
            .animation(.easeInOut(duration: 0.1), value: blinkPhase)
    }
    
    @ViewBuilder
    private var stateOverlay: some View {
        switch state {
        case .listening:
            // Slight lean forward visual cue
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: size * 0.8, height: size * 0.8)
                .offset(x: size * 0.05)
        
        case .thinking:
            // Thought indicator dots
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 4, height: 4)
                        .offset(y: sin(Double(i)) * 3)
                }
            }
            .offset(y: -size * 0.35)
        
        case .concerned:
            // Subtle sweat drop / concern indicator
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: size * 0.12))
                .foregroundColor(.orange.opacity(0.7))
                .offset(x: size * 0.3, y: -size * 0.3)
        
        default:
            EmptyView()
        }
    }
    
    private func startIdleAnimations() {
        // Random blinking every 3-7 seconds
        scheduleNextBlink()
        
        // Wave hint after 5s idle
        if state == .idle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation(.easeInOut(duration: 0.5).repeatCount(3, autoreverses: true)) {
                    wavePhase = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    wavePhase = false
                }
            }
        }
    }
    
    private func scheduleNextBlink() {
        let delay = Double.random(in: 3...7)
        idleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                blinkPhase = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    blinkPhase = false
                }
                scheduleNextBlink()
            }
        }
    }
    
    private func handleStateChange() {
        if state == .celebrating {
            HapticStyle.success.trigger()
        }
    }
}

// MARK: - State Animation Modifier

private struct StateAnimationModifier: ViewModifier {
    let state: MascotState
    let size: CGFloat
    
    @State private var rotation: Double = 0
    @State private var bounceOffset: CGFloat = 0
    @State private var scale: CGFloat = 1.0
    @State private var tilt: Double = 0
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation + tilt))
            .offset(y: bounceOffset)
            .scaleEffect(scale)
            .onAppear {
                applyIdleAnimation()
            }
            .onChange(of: state) { newState in
                applyStateAnimation(newState)
            }
    }
    
    private func applyIdleAnimation() {
        // Breathing: 1.0 → 1.02, 4s cycle
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            scale = 1.02
        }
    }
    
    private func applyStateAnimation(_ state: MascotState) {
        // Reset first
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            rotation = 0
            bounceOffset = 0
            tilt = 0
        }
        
        switch state {
        case .idle:
            applyIdleAnimation()
            
        case .listening:
            // Lean forward
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                tilt = 8
                scale = 1.05
            }
            
        case .thinking:
            // Subtle bounce
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                bounceOffset = -6
            }
            
        case .celebrating:
            // Quick spin + bounce
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                rotation = 360
                scale = 1.15
                bounceOffset = -12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    rotation = 0
                    scale = 1.0
                    bounceOffset = 0
                }
            }
            
        case .concerned:
            // Head tilt
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                tilt = -15
                scale = 0.98
            }
        }
    }
}

private extension View {
    func applyStateAnimation(state: MascotState, size: CGFloat) -> some View {
        modifier(StateAnimationModifier(state: state, size: size))
    }
}

// MARK: - Kuro Concierge Mark

/// The iconic Kuro concierge icon
struct KuroConciergeMarkExperimental: View {
    let size: CGFloat
    let color: Color
    
    var body: some View {
        Image(systemName: "sparkles.square.filled.on.square")
            .font(.system(size: size, weight: .medium))
            .foregroundColor(color)
    }
}

// MARK: - Main Component

/// The complete Kuro Concierge Mascot component
struct KuroConciergeMascot: View {
    @Binding var isExpanded: Bool
    @Binding var offset: CGSize
    
    let state: MascotState
    let onTap: () -> Void
    
    // Configuration
    private let orbSize: CGFloat = 56
    private let panelWidth: CGFloat = 316
    private let panelHeight: CGFloat = 148
    private let screenBounds: CGRect
    
    // Animation states
    @State private var ringOpacity: Double = 0.25
    @State private var ringScale: CGFloat = 0.96
    @State private var panelScale: CGFloat = 0.8
    @State private var panelOpacity: Double = 0
    @State private var hintOpacity: Double = 0
    
    public init(
        isExpanded: Binding<Bool>,
        offset: Binding<CGSize>,
        state: MascotState,
        screenBounds: CGRect = UIScreen.main.bounds,
        onTap: @escaping () -> Void
    ) {
        self._isExpanded = isExpanded
        self._offset = offset
        self.state = state
        self.screenBounds = screenBounds
        self.onTap = onTap
    }
    
    var body: some View {
        ZStack {
            if isExpanded {
                expandedPanel
            } else {
                floatingOrb
            }
        }
        .onChange(of: isExpanded) { expanded in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                panelScale = expanded ? 1.0 : 0.8
                panelOpacity = expanded ? 1.0 : 0
            }
        }
        .onAppear {
            // Show hint after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    hintOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        hintOpacity = 0
                    }
                }
            }
            
            // Start ring pulse animation
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                ringOpacity = 0.65
                ringScale = 1.08
            }
        }
    }
    
    // MARK: - Floating Orb
    
    @ViewBuilder
    private var floatingOrb: some View {
        ZStack {
            // Pulsing ring
            Circle()
                .stroke(Color.accentColor.opacity(ringOpacity), lineWidth: 2)
                .frame(width: orbSize * ringScale, height: orbSize * ringScale)
            
            // Main orb
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: orbSize, height: orbSize)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            
            // Mascot face or icon
            if state == .idle {
                KuroConciergeMarkExperimental(size: 24, color: .primary)
            } else {
                KuroMascotFace(state: state, size: orbSize * 0.7)
            }
        }
        .modifier(
            BoundedDraggableModifier(
                offset: $offset,
                bounds: draggableBounds,
                onDragEnd: nil
            )
        )
        .modifier(
            MicroInteractionModifier(
                scale: 0.96,
                hapticStyle: .light,
                animationDuration: 0.1,
                onTap: onTap
            )
        )
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityHint("Double tap to open concierge")
        .overlay(
            // Hint tooltip
            Text("Tap for help")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .offset(y: -orbSize * 0.8)
                .opacity(hintOpacity)
                .animation(.easeInOut(duration: 0.3), value: hintOpacity),
            alignment: .top
        )
    }
    
    // MARK: - Expanded Panel
    
    @ViewBuilder
    private var expandedPanel: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                HStack(spacing: 8) {
                    KuroMascotFace(state: state, size: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONCIERGE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        Text(stateLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // Close button
                Button(action: {
                    HapticStyle.light.trigger()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        isExpanded = false
                    }
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            // Description
            Text("Your personal anime & manga assistant. Ask for recommendations, track your progress, or get help navigating.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Spacer()
            
            // Action button
            Button(action: {
                HapticStyle.medium.trigger()
                // Start chat action
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "message.fill")
                    Text("START CHAT")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .buttonStyle(ConciergeButtonStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .scaleEffect(panelScale)
        .opacity(panelOpacity)
        .modifier(
            BoundedDraggableModifier(
                offset: $offset,
                bounds: draggableBounds,
                onDragEnd: nil
            )
        )
        .accessibilityLabel("Concierge panel")
        .accessibilityHint("Drag to move, tap Start Chat to begin conversation")
    }
    
    // MARK: - Helpers
    
    private var stateLabel: String {
        switch state {
        case .idle: return "Ready to help"
        case .listening: return "Listening..."
        case .thinking: return "Thinking..."
        case .celebrating: return "Great news!"
        case .concerned: return "Need help?"
        }
    }
    
    private var draggableBounds: CGRect {
        let margin: CGFloat = 20
        let size = isExpanded ? panelWidth : orbSize
        let height = isExpanded ? panelHeight : orbSize
        
        return CGRect(
            x: -screenBounds.width/2 + size/2 + margin,
            y: -screenBounds.height/2 + height/2 + margin,
            width: screenBounds.width - size - margin * 2,
            height: screenBounds.height - height - margin * 2
        )
    }
}

// MARK: - Custom Button Style

struct ConciergeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    HapticStyle.light.trigger()
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply micro-interaction tap effect
    func microInteraction(
        scale: CGFloat = 0.96,
        haptic: HapticStyle = .light,
        duration: Double = 0.1,
        onTap: @escaping () -> Void
    ) -> some View {
        modifier(MicroInteractionModifier(
            scale: scale,
            hapticStyle: haptic,
            animationDuration: duration,
            onTap: onTap
        ))
    }
    
    /// Apply card selection effect
    func cardSelection(isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        modifier(CardSelectionModifier(isSelected: isSelected, onTap: onTap))
    }
    
    /// Apply input focus glow
    func inputFocus(isFocused: Bool, color: Color = .accentColor, blur: CGFloat = 8) -> some View {
        modifier(InputFocusModifier(isFocused: isFocused, glowColor: color, maxBlur: blur))
    }
    
    /// Apply bounded draggable behavior
    func boundedDraggable(
        offset: Binding<CGSize>,
        bounds: CGRect,
        onDragEnd: ((CGSize) -> Void)? = nil
    ) -> some View {
        modifier(BoundedDraggableModifier(
            offset: offset,
            bounds: bounds,
            onDragEnd: onDragEnd
        ))
    }
}

// MARK: - Preview

#Preview("All States") {
    struct StatePreview: View {
        @State private var isExpanded = false
        @State private var offset: CGSize = .zero
        @State private var selectedState: MascotState = .idle
        
        let states: [MascotState] = [.idle, .listening, .thinking, .celebrating, .concerned]
        
        var body: some View {
            ZStack {
                // Background
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.15),
                        Color(red: 0.05, green: 0.05, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text("Kuro Concierge Mascot")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Tap states to change, tap mascot to expand")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // State selector
                    HStack(spacing: 12) {
                        ForEach(states, id: \.self) { state in
                            StateButton(
                                state: state,
                                isSelected: selectedState == state
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedState = state
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                    
                    // Demo interactions
                    VStack(spacing: 12) {
                        Text("Micro-Interactions")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        HStack(spacing: 16) {
                            Button("Light Haptic") { HapticStyle.light.trigger() }
                            Button("Medium Haptic") { HapticStyle.medium.trigger() }
                            Button("Success Haptic") { HapticStyle.success.trigger() }
                            Button("Click Haptic") { HapticStyle.click.trigger() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                        
                        HStack(spacing: 16) {
                            Text("Card Selection")
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                                .cardSelection(isSelected: false) {}
                            
                            Text("Input Focus")
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                                .inputFocus(isFocused: true)
                        }
                    }
                    
                    Spacer()
                }
                
                // The mascot
                KuroConciergeMascot(
                    isExpanded: $isExpanded,
                    offset: $offset,
                    state: selectedState,
                    onTap: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            isExpanded.toggle()
                        }
                    }
                )
            }
        }
    }
    
    struct StateButton: View {
        let state: MascotState
        let isSelected: Bool
        let action: () -> Void
        
        var label: String {
            switch state {
            case .idle: return "Idle"
            case .listening: return "Listening"
            case .thinking: return "Thinking"
            case .celebrating: return "Celebrate"
            case .concerned: return "Concerned"
            }
        }
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 8) {
                    KuroMascotFace(state: state, size: 40)
                    Text(label)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(isSelected ? .accentColor : .secondary)
        }
    }
    
    return StatePreview()
}

#Preview("Expanded Panel") {
    struct ExpandedPreview: View {
        @State private var isExpanded = true
        @State private var offset: CGSize = .zero
        
        var body: some View {
            ZStack {
                Color.black.opacity(0.8).ignoresSafeArea()
                
                KuroConciergeMascot(
                    isExpanded: $isExpanded,
                    offset: $offset,
                    state: .idle,
                    onTap: {}
                )
            }
        }
    }
    
    return ExpandedPreview()
}

#Preview("Floating Orb") {
    struct OrbPreview: View {
        @State private var isExpanded = false
        @State private var offset: CGSize = .zero
        @State private var state: MascotState = .idle
        
        var body: some View {
            ZStack {
                Color.black.opacity(0.8).ignoresSafeArea()
                
                KuroConciergeMascot(
                    isExpanded: $isExpanded,
                    offset: $offset,
                    state: state,
                    onTap: {}
                )
            }
            .onAppear {
                // Cycle through states
                let states: [MascotState] = [.idle, .listening, .thinking, .celebrating, .concerned]
                var index = 0
                Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                    index = (index + 1) % states.count
                    withAnimation {
                        state = states[index]
                    }
                }
            }
        }
    }
    
    return OrbPreview()
}

#endif
