import SwiftUI

// MARK: - External Links Section for Media Detail Views
// Shows "View on AniList" and "View on MyAnimeList" links.

struct ExternalLinksSection: View {
    let anilistId: Int
    let malId: Int?
    let mediaType: String // "anime" or "manga"

    private var anilistURL: URL? {
        URL(string: "https://anilist.co/\(mediaType)/\(anilistId)")
    }

    private var malURL: URL? {
        guard let malId else { return nil }
        return URL(string: "https://myanimelist.net/\(mediaType)/\(malId)")
    }

    var body: some View {
        let hasAnyLink = anilistURL != nil || malURL != nil
        if hasAnyLink {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                EditorialLayout.divider()

                Text("VIEW ON")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.black.opacity(0.3))

                HStack(spacing: 12) {
                    if let url = anilistURL {
                        ExternalLinkButton(title: "AniList", url: url)
                    }
                    if let url = malURL {
                        ExternalLinkButton(title: "MyAnimeList", url: url)
                    }
                }
            }
        }
    }
}

private struct ExternalLinkButton: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                Text(title.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.2)
            }
            .foregroundColor(.black.opacity(0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .accessibilityLabel("View on \(title)")
    }
}
