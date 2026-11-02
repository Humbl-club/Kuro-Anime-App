// CompactAnimeCard: shared connected card (fixed-height poster, title, year and episode/chapter
// count) for horizontal scrolls. Moved verbatim from EditorialDiscoverView.swift (placement only;
// see docs/plans/2026-10-05-modular-architecture-large-file-review.md §9 item 3).
//
// Reads: no store owners. Environment values `\.kuroSuppressCardTaps` (tap guard) and
// `\.kuroRoutes` (`openMedia` on tap; the nearest `.routePresenter()` presents the detail).
// Consumers: EditorialDiscoverView.swift (`CompactHorizontalMangaSection`), TastePicksView.swift.
// Connected, not presentational: changing its interface is a separate (typed-navigation) decision.

import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Compact Anime Card (for horizontal scrolls)
// Small, efficient, shows key info
struct CompactAnimeCard: View {
    let media: any MediaDisplayable
    var cardWidth: CGFloat = 110
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    var body: some View {
        let imageHeight: CGFloat = floor(cardWidth / 0.6667)
        // Keep a fixed total height so horizontal rows never "wobble" based on title wrapping.
        let titleHeight: CGFloat = 32
        let metaHeight: CGFloat = 12
        let innerSpacingImageToText: CGFloat = 7
        let innerSpacingTitleToMeta: CGFloat = 3
        let totalHeight = imageHeight + innerSpacingImageToText + titleHeight + innerSpacingTitleToMeta + metaHeight

        VStack(alignment: .leading, spacing: 7) {
                // Image with score badge
                ZStack(alignment: .topTrailing) {
                    KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 420) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth, height: imageHeight)
                                .clipped()
                        case .failure, .empty:
                            Rectangle()
                                .fill(Color.black.opacity(0.05))
                                .frame(width: cardWidth, height: imageHeight)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: cardWidth, height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    if let rating = media.rating, rating > 0 {
                        KuroScoreBadge(score: rating)
                            .padding(6)
                    }
                }

                // Title and info
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(2)
                        .frame(height: titleHeight, alignment: .top)

                    HStack(spacing: 4) {
                        Text(media.year)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.black.opacity(0.6))

                        if let episodes = media.episodes, episodes > 0 {
                            Text("·")
                                .foregroundColor(.black.opacity(0.4))
                            Text("\(episodes) eps")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.black.opacity(0.6))
                        } else if let chapters = media.chapters, chapters > 0 {
                            Text("·")
                                .foregroundColor(.black.opacity(0.4))
                            Text("\(chapters) ch")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.black.opacity(0.6))
                        }
                    }
                    .frame(height: metaHeight, alignment: .topLeading)
                }
                .frame(width: cardWidth)
        }
        .frame(width: cardWidth, height: totalHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .kuroDeliberateTap {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(media.libraryKey))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText())
        .accessibilityHint("Opens details")
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityLabelText() -> Text {
        var parts: [String] = []
        parts.append(media.title)
        if !media.year.isEmpty { parts.append(media.year) }
        if let episodes = media.episodes, episodes > 0 { parts.append("\(episodes) episodes") }
        if let chapters = media.chapters, chapters > 0 { parts.append("\(chapters) chapters") }
        if let rating = media.rating, rating > 0 { parts.append(String(format: "Rating %.1f", rating)) }
        return Text(parts.joined(separator: ", "))
    }
}
