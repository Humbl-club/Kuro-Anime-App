import SwiftUI

// MARK: - External Links Section for Media Detail Views
// Shows optional reference links (MAL), separate from legal watch/read actions.

struct ExternalLinksSection: View {
    /// The Kuro id of the title (outbound-link telemetry; AniList ids are private).
    let mediaId: Int
    let malId: Int?
    let mediaType: String // "anime" or "manga"

    /// One reference link.
    struct Reference: Equatable {
        let title: String
        let url: URL
    }

    /// The reference links of a title: MyAnimeList only (catalogue Task 15d removed AniList).
    static func references(malId: Int?, mediaType: String) -> [Reference] {
        guard let malId, let url = URL(string: "https://myanimelist.net/\(mediaType)/\(malId)") else { return [] }
        return [Reference(title: "MyAnimeList", url: url)]
    }

    var body: some View {
        let links = Self.references(malId: malId, mediaType: mediaType)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                EditorialLayout.divider()

                Text(KuroLocale.text("REFERENCE", "NACHSCHLAGEN"))
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.kuroInkQuiet)

                HStack(spacing: 12) {
                    ForEach(links, id: \.title) { link in
                        ExternalLinkButton(title: link.title, url: link.url, mediaType: mediaType, mediaId: mediaId)
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
    @Environment(OutboundLinkTelemetry.self) private var outboundLinks

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.kuroCustom(10, weight: .medium, maxSize: 16))
                Text(title.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.2)
            }
            .foregroundColor(.kuroTextSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.kuroBlack04)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.kuroBlack08, lineWidth: 0.5)
                    )
            )
        }
        .accessibilityLabel(KuroLocale.text("Reference link: \(title)", "Nachschlagen bei \(title)"))
        .simultaneousGesture(TapGesture().onEnded {
            outboundLinks.recordOutboundLink(
                mediaType: mediaType.uppercased(),
                mediaId: mediaId,
                linkKind: "external_reference",
                provider: title
            )
        })
    }
}
