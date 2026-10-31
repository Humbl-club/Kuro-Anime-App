// GridAnimeCard: shared connected card (fixed-size poster, saved check, title and meta line)
// for 2-column grids, with a context menu for tracking and clubs. Moved verbatim from
// EditorialDiscoverView.swift (placement only; see
// docs/plans/2026-10-05-modular-architecture-large-file-review.md §9 item 3).
//
// Reads: LibraryStore (`isTracked`, saved state), LibraryActions (context-menu toggle through
// `LibraryViewActions.toggleTracked`), ClubsStore (`myClubs` gates "Add to Club…"). Environment
// values `\.kuroSuppressCardTaps` and `\.kuroRoutes` (`openMedia`, `presentTrackingEditor`,
// `presentAddToClub`; the nearest `.routePresenter()` presents them). It does not read
// SocialActivityStore, ProviderAvailabilityStore or FeatureFlags.
// Consumers: EditorialDiscoverView.swift (`Dense2ColumnSectionFixed`, `Dense2ColumnMangaSectionFixed`,
// `FullSectionView`, `FullMangaSectionView`), BrowseComponents.swift (Browse grid).
// Connected, not presentational: changing its interface is a separate (typed-navigation) decision.

import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Grid Anime Card (for 2-column grids)
// Vertical card optimized for grid layouts with FIXED dimensions
struct GridAnimeCard: View {
    let media: any MediaDisplayable
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(ClubsStore.self) private var clubs
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    private var isInCollection: Bool {
        library.isTracked(media.libraryKey)
    }

    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private func countString(_ value: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var metaLine: String? {
        var parts: [String] = []

        let digits = media.year.filter(\.isNumber)
        if digits.count >= 4 {
            parts.append(String(digits.prefix(4)))
        }

        if let episodes = media.episodes, episodes > 0 {
            parts.append("\(countString(episodes)) eps")
        } else if let chapters = media.chapters, chapters > 0 {
            parts.append("\(countString(chapters)) ch")
        } else if let status = media.statusRaw?.uppercased() {
            if status == "RELEASING" { parts.append("airing") }
            if status == "FINISHED" { parts.append("finished") }
        } else if let format = media.formatRaw, !format.isEmpty {
            parts.append(format.lowercased())
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
                // Image with score - FIXED HEIGHT
                let imageHeight = max(100, floor(cardWidth / 0.7))

                ZStack(alignment: .top) {
                    KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 520) { phase in
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

                    HStack(alignment: .top) {
                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            if let rating = media.rating, rating > 0 {
                                KuroScoreBadge(score: rating)
                            }

                            if isInCollection {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.black.opacity(0.55))
                                    .background(
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 18, height: 18)
                                    )
                            }
                        }
                    }
                    .padding(6)
                }

                // Title and info
                VStack(alignment: .leading, spacing: 2) {
                    Text(KuroCardText.sanitizeTitleForCard(media.title))
                        .font(.system(size: 12, weight: .light, design: .serif))
                        .textCase(.uppercase)
                        .tracking(media.title.count >= 26 ? 0.3 : 0.6)
                        .foregroundColor(.black.opacity(0.9))
                        .lineLimit(2)
                        .minimumScaleFactor(0.92)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                        .frame(height: 32, alignment: .top)

                    if let metaLine {
                        Text(metaLine)
                            .font(.system(size: 9, weight: .light))
                            .foregroundColor(.black.opacity(0.5))
                            .lineLimit(1)
                    }

                }
                .frame(width: cardWidth, alignment: .topLeading)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .top)
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
        .contextMenu {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                LibraryViewActions.toggleTracked(media.libraryKey, actions: libraryActions)
            }) {
                Label(
                    isInCollection ? "Remove from List" : "Quick Add (Planned)",
                    systemImage: isInCollection ? "minus.circle" : "plus.circle"
                )
            }

            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                routes.presentTrackingEditor(TrackingEditorRequest(media: media))
            }) {
                Label(
                    isInCollection ? "Edit List" : "Add to List…",
                    systemImage: "slider.horizontal.3"
                )
            }

            if !clubs.myClubs.isEmpty {
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    routes.presentAddToClub(media.libraryKey)
                }) {
                    Label("Add to Club\u{2026}", systemImage: "person.2.circle")
                }
            }
        }
    }

    private func accessibilityLabelText() -> Text {
        var parts: [String] = []
        parts.append(media.title)
        if !media.year.isEmpty { parts.append(media.year) }
        if let episodes = media.episodes, episodes > 0 { parts.append("\(episodes) episodes") }
        if let chapters = media.chapters, chapters > 0 { parts.append("\(chapters) chapters") }
        if let rating = media.rating, rating > 0 { parts.append(String(format: "Rating %.1f", rating)) }
        if isInCollection { parts.append("Saved") }
        return Text(parts.joined(separator: ", "))
    }
}
