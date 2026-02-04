import SwiftUI

// Minimal Concierge mark (no mascot). Used for the launcher button + overlay header.
struct KuroConciergeMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.10))
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.0)
                        .blendMode(.overlay)
                )

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundColor(.black.opacity(0.70))
                .shadow(color: Color.white.opacity(0.35), radius: 0, x: 0, y: 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

