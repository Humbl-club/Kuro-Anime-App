import SwiftUI

struct ConciergeResponseStage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.66), Color.white.opacity(0.42)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous))
            .padding(.horizontal, KuroDesignSpacing.sm)
            .padding(.top, 2)
    }
}
