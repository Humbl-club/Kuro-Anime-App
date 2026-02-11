import SwiftUI

/// A reusable "glass morphism" surface. Looks best when there's *something* behind it,
/// even if it's just a subtle gradient.
struct KuroGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.kuroSecondaryBackground.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.70),
                                        Color.white.opacity(0.18),
                                        Color.black.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.black.opacity(0.14), radius: 22, x: 0, y: 12)
                    .shadow(color: Color.white.opacity(0.55), radius: 1, x: 0, y: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct KuroGlassPill: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let action: () -> Void

    @State private var isPressed: Bool = false

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.kuroBody(weight: .semibold))
                    .foregroundColor(.black.opacity(0.82))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.kuroCaption(weight: .semibold))
                        .foregroundColor(.black.opacity(0.9))
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.kuroMicro(weight: .regular))
                            .foregroundColor(.black.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.kuroCaption(weight: .semibold))
                    .foregroundColor(.black.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.85), value: isPressed)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.01)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .background(
            Capsule(style: .continuous)
                .fill(Color.kuroSecondaryBackground.opacity(0.96))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.7)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
        )
    }
}

