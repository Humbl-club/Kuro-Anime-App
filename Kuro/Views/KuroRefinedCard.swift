// MARK: - KURO REFINED CARD SYSTEM
// Premium, Elegant, Evolved Design
// Philosophy: "Gallery-quality presentation with editorial restraint"

import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Refined Score Badge
// Monochrome glass chip (Discover P1 color-law cleanup): quiet dark scrim,
// white text, subtle hairline. One recipe shared by every Discover/Browse card.
struct KuroScoreBadge: View {
    let score: Double?

    private var displayScore: String {
        guard let score = score, score > 0 else { return "--" }
        return String(format: "%.1f", score)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 7, weight: .bold))
            Text(displayScore)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(.kuroWhite)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.kuroBlack45)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.kuroWhite20, lineWidth: 0.5)
        )
    }
}

// MARK: - Refined Compact Card (Horizontal Scroll)
struct KuroCompactCard: View {
    let media: any MediaDisplayable
    var width: CGFloat = 110

    @State private var isPressed = false
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(FeatureFlags.self) private var flags
    @Environment(ClubsStore.self) private var clubs
    @Environment(SocialActivityStore.self) private var social
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    private var mediaType: String {
        media.kind.rawValue
    }

    private var isInCollection: Bool {
        library.isTracked(media.libraryKey)
    }

    private var height: CGFloat {
        width / 0.7
    }

    private var metaLine: String? {
        var parts: [String] = []

        let digits = media.year.filter(\.isNumber)
        if digits.count >= 4 {
            parts.append(String(digits.prefix(4)))
        }

        if let episodes = media.episodes, episodes > 0 {
            parts.append("\(KuroCardText.countString(episodes)) eps")
        } else if let chapters = media.chapters, chapters > 0 {
            parts.append("\(KuroCardText.countString(chapters)) ch")
        } else if let status = media.statusRaw?.uppercased() {
            if status == "RELEASING" { parts.append(media.kind == .manga ? KuroLocale.text("publishing", "erscheint") : KuroLocale.text("airing", "läuft")) }
            if status == "FINISHED" { parts.append("finished") }
        } else if let format = media.formatRaw, !format.isEmpty {
            parts.append(format.lowercased())
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 300) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                    case .failure, .empty:
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                            .frame(width: width, height: height)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                HStack(alignment: .top) {
                    Spacer()
                    if let rating = media.rating, rating > 0 {
                        KuroScoreBadge(score: rating)
                    }
                }
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(KuroCardText.sanitizeTitleForCard(media.title))
                    .font(.system(size: 12, weight: .light, design: .serif))
                    .textCase(.uppercase)
                    .tracking(media.title.count >= 24 ? 0.25 : 0.55)
                    .foregroundColor(.black.opacity(0.9))
                    .lineLimit(2)
                    .minimumScaleFactor(0.90)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .frame(height: 32, alignment: .top)

                if let metaLine {
                    Text(metaLine)
                        .font(.system(size: 9, weight: .light))
                        .foregroundColor(.black.opacity(0.5))
                        .lineLimit(1)
                }

                if flags.isSocialActivityV1Enabled {
                    let count = social.friendCount(mediaId: media.id, mediaType: mediaType.uppercased())
                    if count > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2")
                                .font(.system(size: 8, weight: .regular))
                            Text("\(count) friend\(count == 1 ? "" : "s")")
                                .font(.system(size: 9, weight: .light))
                        }
                        .foregroundColor(.black.opacity(0.40))
                    }
                }

                if flags.isStreamingAvailabilityV1Enabled {
                    if let provider = availability.bestProviderDisplayName(mediaId: media.id, mediaType: mediaType.uppercased()) {
                        HStack(spacing: 3) {
                            Image(systemName: "play.tv")
                                .font(.system(size: 8, weight: .regular))
                            Text(provider)
                                .font(.system(size: 9, weight: .light))
                        }
                        .foregroundColor(.black.opacity(0.40))
                    }
                }
            }
            .frame(width: width, alignment: .topLeading)
            .padding(.top, 10)
        }
        .contentShape(Rectangle())
        .kuroDeliberateTap {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(media.libraryKey))
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .opacity(isPressed ? 0.95 : 1.0)
        .accessibilityAddTraits(.isButton)
        .pressable($isPressed)
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
                    isInCollection ? "Edit List" : "Add to List\u{2026}",
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
}

// MARK: - Refined Hero Card
struct KuroHeroCard: View {
    let media: any MediaDisplayable
    let width: CGFloat

    @State private var isPressed = false
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(FeatureFlags.self) private var flags
    @Environment(ClubsStore.self) private var clubs
    @Environment(SocialActivityStore.self) private var social
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    private var mediaType: String {
        media.kind.rawValue
    }

    private var isInCollection: Bool {
        library.isTracked(media.libraryKey)
    }

    private var height: CGFloat {
        max(220, floor(width * 0.54))
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 700) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                default:
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                        .frame(width: width, height: height)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            // Gradient overlay
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text("FEATURED")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.8))
                
                Text(media.title)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(media.year)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                    
                    if let rating = media.rating, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                    }
                    
                    if let episodes = media.episodes, episodes > 0 {
                        Text("· \(episodes) episodes")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.85))
                    }

                    if flags.isSocialActivityV1Enabled {
                        let count = social.friendCount(mediaId: media.id, mediaType: mediaType.uppercased())
                        if count > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "person.2")
                                    .font(.system(size: 8, weight: .regular))
                                Text("\(count) friend\(count == 1 ? "" : "s")")
                                    .font(.system(size: 9, weight: .light))
                            }
                            .foregroundColor(.white.opacity(0.65))
                        }
                    }
                }
            }
            .padding(16)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .kuroDeliberateTap {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.medium)
            routes.openMedia(MediaRoute(media.libraryKey))
        }
        .scaleEffect(isPressed ? 0.99 : 1.0)
        .opacity(isPressed ? 0.95 : 1.0)
        .accessibilityAddTraits(.isButton)
        .pressable($isPressed, duration: 0.15)
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
                    isInCollection ? "Edit List" : "Add to List\u{2026}",
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
}

// MARK: - Press Effect Modifier
struct PressableModifier: ViewModifier {
    @Binding var isPressed: Bool
    let minimumDuration: Double
    
    func body(content: Content) -> some View {
        content
            .onLongPressGesture(
                minimumDuration: minimumDuration,
                maximumDistance: .infinity,
                pressing: { pressing in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = pressing
                    }
                },
                perform: {}
            )
    }
}

extension View {
    func pressable(_ isPressed: Binding<Bool>, duration: Double = 0.1) -> some View {
        modifier(PressableModifier(isPressed: isPressed, minimumDuration: duration))
    }
}
