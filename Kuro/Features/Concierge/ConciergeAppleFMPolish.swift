// NOTE: Experimental prototype UI. Debug-only to avoid shipping unfinished UX.
#if DEBUG
// MARK: - ConciergeAppleFMPolish.swift
// Kuro iOS App - Apple Foundation Models Integration Polish
// iOS 26+ Compatible

import SwiftUI

// MARK: - Data Models

struct FMDisambiguationItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let posterURL: String?
    let userContext: String?
}

struct FMDisambiguationCandidate: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let year: Int
    let format: String
    let episodeCount: Int
    let confidence: Double
    let posterURL: String?
}

enum DisambiguationState: Equatable {
    case thinking
    case autoSelected(candidate: FMDisambiguationCandidate, reasoning: String)
    case manualSelection(candidates: [FMDisambiguationCandidate])
    case completed
}

// MARK: - DisambiguationCard

struct DisambiguationCard: View {
    let item: FMDisambiguationItem
    let state: DisambiguationState
    let onCancel: () -> Void
    let onManualSelect: (FMDisambiguationCandidate) -> Void
    let onConfirm: () -> Void
    
    @State private var sparkleTrigger: Bool = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var badgeOpacity: Double = 0
    @State private var reasoningOffset: CGFloat = 20
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                posterImage
                
                VStack(alignment: .leading, spacing: 4) {
                    titleSection
                    detailSection
                }
                
                Spacer()
                
                statusIndicator
            }
            
            if case .autoSelected(_, let reasoning) = state {
                reasoningSection(reasoning: reasoning)
            }
        }
        .padding(16)
        .background(glassBackground)
        .overlay(sparkleOverlay)
        .onChange(of: state) { oldValue, newValue in
            handleStateTransition(from: oldValue, to: newValue)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state)
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var posterImage: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 50, height: 70)
            .overlay(
                Group {
                    if let url = item.posterURL {
                        AsyncImage(url: URL(string: url)) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            )
    }
    
    @ViewBuilder
    private var titleSection: some View {
        Text(item.title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
    
    @ViewBuilder
    private var detailSection: some View {
        Group {
            switch state {
            case .thinking:
                DisambiguationThinkingIndicator()
                
            case .autoSelected(let candidate, _):
                HStack(spacing: 6) {
                    Text("\(candidate.year)")
                    Text("·")
                    Text(candidate.format)
                    Text("·")
                    Text("\(candidate.episodeCount) ep")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                
            case .manualSelection:
                Text("Multiple matches found")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                    
            case .completed:
                Text("Added to library")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            }
        }
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        ZStack {
            switch state {
            case .thinking:
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel auto-selection")
                
            case .autoSelected(let candidate, _):
                ZStack {
                    // Confidence ring
                    ConfidenceRing(confidence: candidate.confidence)
                        .frame(width: 28, height: 28)
                    
                    // Checkmark with bounce
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(checkmarkScale)
                }
                
            case .manualSelection:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                    
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
            }
        }
    }
    
    @ViewBuilder
    private func reasoningSection(reasoning: String) -> some View {
        HStack(spacing: 6) {
            // Auto badge
            Text("✓ Auto")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(.green.opacity(0.15))
                )
                .opacity(badgeOpacity)
            
            Text("Selected based on your text")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            Text("\"\(reasoning)\"")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .offset(y: reasoningOffset)
        .opacity(1.0 - (Double(reasoningOffset) / 20.0))
    }
    
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
    
    @ViewBuilder
    private var sparkleOverlay: some View {
        if sparkleTrigger {
            SparkleEffect(isActive: sparkleTrigger)
                .allowsHitTesting(false)
        }
    }
    
    // MARK: - State Handling
    
    private func handleStateTransition(from oldState: DisambiguationState, to newState: DisambiguationState) {
        if case .autoSelected = newState, oldState == .thinking {
            // Trigger sparkle animation
            sparkleTrigger = true
            
            // Animate checkmark bounce
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.1)) {
                checkmarkScale = 1.0
            }
            
            // Fade in badge
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                badgeOpacity = 1.0
            }
            
            // Slide up reasoning
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.25)) {
                reasoningOffset = 0
            }
            
            // Reset sparkle after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                sparkleTrigger = false
            }
        } else {
            // Reset states
            checkmarkScale = 0
            badgeOpacity = 0
            reasoningOffset = 20
        }
    }
}

// MARK: - ThinkingIndicator

struct DisambiguationThinkingIndicator: View {
    @State private var dotCount = 0
    @State private var rotation: Double = 0
    @State private var dotTask: Task<Void, Never>?
    
    var body: some View {
        HStack(spacing: 8) {
            Text("Thinking" + String(repeating: ".", count: dotCount))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            
            Spacer()
            
            // Spinner
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                    
                    dotTask?.cancel()
                    dotTask = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            await MainActor.run {
                                dotCount = (dotCount + 1) % 4
                            }
                        }
                    }
                }
                .onDisappear {
                    dotTask?.cancel()
                    dotTask = nil
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thinking, please wait")
    }
}

// MARK: - ConfidenceRing

struct ConfidenceRing: View {
    let confidence: Double
    
    private var color: Color {
        switch confidence {
        case 0.9...1.0: return .green
        case 0.7..<0.9: return .orange
        default: return .yellow
        }
    }
    
    private var showReviewLabel: Bool {
        confidence < 0.7
    }
    
    var body: some View {
        Circle()
            .trim(from: 0, to: confidence)
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .background(
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 3)
            )
    }
}

// MARK: - SparkleEffect

struct SparkleEffect: View {
    var isActive: Bool
    let particleCount = 12
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width - 44, y: size.height / 2)
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                for i in 0..<particleCount {
                    let angle = (Double(i) / Double(particleCount)) * 2 * .pi
                    let progress = fmod(time + Double(i) * 0.05, 0.6) / 0.6
                    
                    let distance = 30 * progress
                    let x = center.x + cos(angle) * distance
                    let y = center.y + sin(angle) * distance
                    
                    let opacity = 1 - progress
                    let scale = 1 - progress * 0.5
                    
                    var path = Path()
                    let starPoints = 4
                    let outerRadius: CGFloat = 4 * scale
                    let innerRadius: CGFloat = 2 * scale
                    
                    for j in 0..<(starPoints * 2) {
                        let pointAngle = Double(j) * .pi / Double(starPoints) - .pi / 2
                        let radius = j % 2 == 0 ? outerRadius : innerRadius
                        let px = x + cos(pointAngle) * radius
                        let py = y + sin(pointAngle) * radius
                        
                        if j == 0 {
                            path.move(to: CGPoint(x: px, y: py))
                        } else {
                            path.addLine(to: CGPoint(x: px, y: py))
                        }
                    }
                    path.closeSubpath()
                    
                    context.fill(path, with: .color(.yellow.opacity(opacity)))
                }
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: isActive)
    }
}

// MARK: - SuccessToast

struct SuccessToast: View {
    let count: Int
    let onUndo: () -> Void
    let onView: (() -> Void)?
    let autoDismiss: Bool
    
    @State private var isVisible = false
    @State private var countdownProgress: Double = 1.0
    @State private var showConfetti = false
    
    private let dismissDuration: Double = 4.0
    
    init(
        count: Int,
        onUndo: @escaping () -> Void,
        onView: (() -> Void)? = nil,
        autoDismiss: Bool = true
    ) {
        self.count = count
        self.onUndo = onUndo
        self.onView = onView
        self.autoDismiss = autoDismiss
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.green)
                }
                
                // Message
                VStack(alignment: .leading, spacing: 2) {
                    Text("Added \(count) title\(count == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("To your library")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Actions
                HStack(spacing: 8) {
                    if onView != nil {
                        Button(action: {
                            onView?()
                            dismiss()
                        }) {
                            Text("View")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            isVisible = false
                        }
                        onUndo()
                    }) {
                        Text("Undo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Countdown progress bar
            if autoDismiss {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.green.opacity(0.5))
                        .frame(width: geo.size.width * countdownProgress, height: 3)
                }
                .frame(height: 3)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .overlay(confettiOverlay)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            animateIn()
        }
    }
    
    @ViewBuilder
    private var confettiOverlay: some View {
        if showConfetti {
            ConfettiEffect()
                .allowsHitTesting(false)
        }
    }
    
    private func animateIn() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isVisible = true
            showConfetti = true
        }
        
        // Hide confetti after burst
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                showConfetti = false
            }
        }
        
        if autoDismiss {
            // Animate countdown
            withAnimation(.linear(duration: dismissDuration)) {
                countdownProgress = 0
            }
            
            // Auto dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + dismissDuration) {
                dismiss()
            }
        }
    }
    
    private func dismiss() {
        withAnimation(.spring(response: 0.3)) {
            isVisible = false
        }
    }
}

#endif

// MARK: - ConfettiEffect

struct ConfettiEffect: View {
    let particleCount = 30
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618033988749895 // Golden ratio for distribution
                    let delay = Double(i) * 0.02
                    let progress = max(0, min(1, (time - delay) / 0.8))
                    
                    guard progress > 0 else { continue }
                    
                    let angle = seed * 2 * .pi
                    let velocity = 60 + Double(i % 5) * 20
                    let distance = velocity * progress
                    
                    let x = center.x + cos(angle) * distance
                    let y = center.y + sin(angle) * distance - 30 * progress * progress // Gravity arc
                    
                    let opacity = 1 - progress
                    let rotation = time * 5 + Double(i)
                    
                    let colors: [Color] = [.green, .yellow, .orange, .blue, .purple, .pink]
                    let color = colors[i % colors.count]
                    
                    var rect = Path()
                    let w: CGFloat = 6
                    let h: CGFloat = 4
                    rect.move(to: CGPoint(x: x - w/2, y: y - h/2))
                    rect.addLine(to: CGPoint(x: x + w/2, y: y - h/2))
                    rect.addLine(to: CGPoint(x: x + w/2, y: y + h/2))
                    rect.addLine(to: CGPoint(x: x - w/2, y: y + h/2))
                    rect.closeSubpath()
                    
                    var transform = CGAffineTransform(translationX: x, y: y)
                    transform = transform.rotated(by: rotation)
                    transform = transform.translatedBy(x: -x, y: -y)
                    
                    context.fill(rect.applying(transform), with: .color(color.opacity(opacity)))
                }
            }
        }
    }
}

// MARK: - UndoToast

struct UndoToast: View {
    let count: Int
    let onComplete: () -> Void
    
    @State private var isVisible = false
    @State private var reverseAnimation = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            
            Text("Undid \(count) addition\(count == 1 ? "" : "s")")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(reverseAnimation ? 0.95 : 1)
        .onAppear {
            withAnimation(.spring(response: 0.3)) {
                isVisible = true
            }
            
            // Reverse animation effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    reverseAnimation = true
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isVisible = false
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onComplete()
            }
        }
    }
}

// MARK: - Preview

#Preview("Disambiguation Flow") {
    DisambiguationFlowPreview()
}

#Preview("Toast Variations") {
    ToastPreview()
}

// MARK: - Preview Helpers

private struct DisambiguationFlowPreview: View {
    @State private var state: DisambiguationState = .thinking
    @State private var showToast = false
    @State private var showUndo = false
    
    let item = FMDisambiguationItem(
        title: "Hunter x Hunter",
        posterURL: nil,
        userContext: "watched recently"
    )
    
    let candidate = FMDisambiguationCandidate(
        title: "Hunter x Hunter",
        year: 2011,
        format: "TV",
        episodeCount: 148,
        confidence: 0.94,
        posterURL: nil
    )
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
                DisambiguationCard(
                    item: item,
                    state: state,
                    onCancel: {
                        print("Cancelled")
                    },
                    onManualSelect: { _ in
                        print("Manual selected")
                    },
                    onConfirm: {
                        showToast = true
                    }
                )
                .padding(.horizontal, 20)
                
                // Control buttons for preview
                VStack(spacing: 8) {
                    Button("Trigger Thinking → Auto") {
                        state = .thinking
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            state = .autoSelected(candidate: candidate, reasoning: "watched recently")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Show Success Toast") {
                        showToast = true
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Show Undo Toast") {
                        showUndo = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                
                Spacer()
                
                // Toasts overlay
                VStack {
                    if showToast {
                        SuccessToast(
                            count: 12,
                            onUndo: {
                                showToast = false
                                showUndo = true
                            },
                            onView: {
                                print("View tapped")
                            }
                        )
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    if showUndo {
                        UndoToast(count: 12) {
                            showUndo = false
                        }
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 50)
            }
        }
        .onAppear {
            // Auto-start the demo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    state = .autoSelected(candidate: candidate, reasoning: "watched recently")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        showToast = true
                    }
                }
            }
        }
    }
}

private struct ToastPreview: View {
    @State private var showSuccess = false
    @State private var showUndo = false
    @State private var showNoAutoDismiss = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                Button("Success Toast (12 items)") {
                    showSuccess = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Undo Toast") {
                    showUndo = true
                }
                .buttonStyle(.bordered)
                
                Button("No Auto-Dismiss") {
                    showNoAutoDismiss = true
                }
                .buttonStyle(.bordered)
            }
            
            // Toasts at top
            VStack {
                if showSuccess {
                    SuccessToast(
                        count: 12,
                        onUndo: { showSuccess = false },
                        onView: { print("View") }
                    )
                    .padding(.horizontal, 20)
                }
                
                if showUndo {
                    UndoToast(count: 12) {
                        showUndo = false
                    }
                    .padding(.horizontal, 20)
                }
                
                if showNoAutoDismiss {
                    SuccessToast(
                        count: 5,
                        onUndo: { showNoAutoDismiss = false },
                        autoDismiss: false
                    )
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            .padding(.top, 50)
        }
    }
}
