import SwiftUI

struct ConciergeComposerDock<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.70), Color.black.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.7
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}
