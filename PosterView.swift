import SwiftUI

struct PosterView: View {
    let url: URL?
    var cornerRadius: CGFloat = 12
    var showsShadow: Bool = false
    var badgeText: String? = nil // e.g., "★ 8.4"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Base placeholder to lock layout
            Rectangle()
                .fill(Color(.secondarySystemBackground))

            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Color.clear
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.secondary)
                @unknown default:
                    Color.clear
                }
            }
            .clipped()

            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(colors: [Color.yellow.opacity(0.95), Color.orange.opacity(0.95)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    .padding(6)
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(showsShadow ? 0.08 : 0.0), radius: showsShadow ? 12 : 0, x: 0, y: showsShadow ? 6 : 0)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 16) {
        PosterView(url: URL(string: "https://picsum.photos/300/450"), showsShadow: true, badgeText: "★ 8.6")
            .frame(width: 140)
        PosterView(url: nil)
            .frame(width: 120)
    }
    .padding()
}
