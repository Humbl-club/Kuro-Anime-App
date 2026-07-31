import SwiftUI

// MARK: - External Links Section for Media Detail Views
// Shows optional reference links (AniList/MAL), separate from legal watch/read actions.

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

                Text("REFERENCE")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.black.opacity(0.3))

                HStack(spacing: 12) {
                    if let url = anilistURL {
                        ExternalLinkButton(title: "AniList", url: url, mediaType: mediaType, mediaId: anilistId)
                    }
                    if let url = malURL {
                        ExternalLinkButton(title: "MyAnimeList", url: url, mediaType: mediaType, mediaId: anilistId)
                    }
                }
            }
        }
    }
}

private struct ExternalLinkButton: View {
    let title: String
    let url: URL
    let mediaType: String
    let mediaId: Int
    @Environment(SupabaseService.self) private var supabaseService

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
        .accessibilityLabel("Reference link: \(title)")
        .simultaneousGesture(TapGesture().onEnded {
            supabaseService.recordOutboundLink(
                mediaType: mediaType.uppercased(),
                mediaId: mediaId,
                linkKind: "external_reference",
                provider: title
            )
        })
    }
}
