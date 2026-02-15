import SwiftUI

// Lightweight, dependency-free toast/banner for non-blocking feedback (e.g. refresh failures).
struct KuroTransientBanner: View {
    let message: String

    var body: some View {
        Text(message.uppercased())
            .font(.kuroMicro(weight: .semibold))
            .tracking(1.4)
            .foregroundColor(.black.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.kuroBackground)
                    .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .accessibilityLabel(message)
    }
}

