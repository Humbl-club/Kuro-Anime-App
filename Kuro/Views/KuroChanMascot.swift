import SwiftUI

/// KURO-CHAN: a tiny 2D mascot used as the Concierge icon and floating assistant.
struct KuroChanMascot: View {
    enum Style: Sendable {
        case refined
        case playful
    }

    let size: CGFloat
    var style: Style = .refined
    var showsSparkle: Bool = true
    var animates: Bool = false
    var showsShadow: Bool = true

    @State private var idle: Bool = false

    var body: some View {
        let refined = style == .refined
        let earW = size * (refined ? 0.34 : 0.38)
        let earH = size * (refined ? 0.30 : 0.34)
        let earY = -size * (refined ? 0.32 : 0.34)
        let earX = size * (refined ? 0.20 : 0.22)

        let eyeW = size * (refined ? 0.24 : 0.20)
        let eyeH = size * (refined ? 0.085 : 0.12)
        let eyeY = -size * (refined ? 0.03 : 0.02)
        let eyeRot: Double = refined ? 10 : 0
        let pupil = size * (refined ? 0.05 : 0.06)
        let pupilInset = size * (refined ? 0.02 : 0.03)

        ZStack {
            // Head
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.92), Color.black.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(showsShadow ? 0.22 : 0.0), radius: showsShadow ? 10 : 0, x: 0, y: showsShadow ? 6 : 0)
                .overlay(
                    // Subtle sheen to make it feel like a premium icon.
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .rotationEffect(.degrees(-18))
                    .offset(x: idle ? -size * 0.10 : size * 0.10)
                    .opacity(animates ? 0.9 : 0.55)
                    .clipShape(Circle())
                )

            // Ears
            Group {
                KuroTriangle()
                    .fill(Color.black.opacity(0.88))
                    .frame(width: earW, height: earH)
                    .offset(x: -earX, y: earY)
                KuroTriangle()
                    .fill(Color.black.opacity(0.84))
                    .frame(width: earW, height: earH)
                    .offset(x: earX, y: earY)
            }
            .shadow(color: Color.black.opacity(showsShadow ? 0.16 : 0.0), radius: showsShadow ? 6 : 0, x: 0, y: showsShadow ? 4 : 0)

            // Eyes
            HStack(spacing: size * 0.20) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(refined ? 0.86 : 0.92))
                    .frame(width: eyeW, height: eyeH)
                    .rotationEffect(.degrees(-eyeRot))
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.75))
                            .frame(width: pupil, height: pupil)
                            .offset(x: -pupilInset, y: refined ? -size * 0.006 : 0)
                    )
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(refined ? 0.86 : 0.92))
                    .frame(width: eyeW, height: eyeH)
                    .rotationEffect(.degrees(eyeRot))
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.75))
                            .frame(width: pupil, height: pupil)
                            .offset(x: pupilInset, y: refined ? -size * 0.006 : 0)
                    )
            }
            .offset(y: eyeY)

            if refined {
                // Minimal nose mark to make the face feel less "toy-like".
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: size * 0.12, height: size * 0.05)
                    .offset(y: size * 0.12)
            }

            if showsSparkle && !refined {
                // Little sparkle
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .offset(x: size * 0.26, y: -size * 0.26)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Kuro-chan")
        .offset(y: animates ? (idle ? -0.8 : 0.6) : 0)
        .scaleEffect(animates ? (idle ? 1.02 : 0.99) : 1.0)
        .onAppear {
            guard animates else { return }
            // Slow, subtle idle motion (keeps it feeling alive without being distracting).
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                idle = true
            }
        }
    }
}

private struct KuroTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
