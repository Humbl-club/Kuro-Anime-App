import SwiftUI

struct PosterView: View {
    let url: URL?
    var cornerRadius: CGFloat = 12
    var showsShadow: Bool = false
    var badgeText: String? = nil // e.g., "★ 8.4"
    var showsShimmer: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Base placeholder to lock layout
            Rectangle()
                .fill(Color.kuroSecondaryBackground)

            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Color.clear
                        if showsShimmer {
                            ShimmerPlaceholder()
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .font(.kuroTitle(weight: .light))
                        .foregroundColor(.kuroTextTertiary)
                @unknown default:
                    Color.clear
                }
            }
            .clipped()

            if let badgeText {
                Text(badgeText)
                    .font(.kuroMicro(weight: .medium))
                    .foregroundColor(.kuroWhite)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(colors: [Color.yellow.opacity(0.95), Color.orange.opacity(0.95)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.kuroBlack.opacity(0.15), radius: 6, x: 0, y: 3)
                    .padding(6)
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.kuroBlack.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: Color.kuroBlack.opacity(showsShadow ? 0.08 : 0.0), radius: showsShadow ? 12 : 0, x: 0, y: showsShadow ? 6 : 0)
        .contentShape(Rectangle())
    }
}

private struct ShimmerPlaceholder: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.kuroBlack.opacity(0.06),
                Color.kuroBlack.opacity(0.12),
                Color.kuroBlack.opacity(0.06)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask(
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.kuroBlack.opacity(0.4),
                            Color.kuroBlack,
                            Color.kuroBlack.opacity(0.4),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: phase)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 300
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        PosterView(url: URL(string: "https://picsum.photos/300/450"), showsShadow: true, badgeText: "★ 8.6", showsShimmer: true)
            .frame(width: 140)
        PosterView(url: nil)
            .frame(width: 120)
    }
    .padding()
}
