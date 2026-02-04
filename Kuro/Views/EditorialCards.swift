// Editorial Card Components
// Vogue/Miu Miu inspired anime/manga cards
// Fashion-forward, dramatic, refined
// Uses tap gestures to preserve TabView navigation

import SwiftUI

// MARK: - Editorial Hero Card
// Large, dramatic, magazine cover style
struct EditorialHeroCard: View {
    let media: any MediaDisplayable
    @State private var isPressed = false
    @State private var showDetail = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Hero Image
                KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 1100) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    case .failure, .empty:
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .overlay(
                                Text("KURO")
                                    .font(.kuroDisplay())
                                    .foregroundColor(.black.opacity(0.1))
                            )
                    @unknown default:
                        EmptyView()
                    }
                }

                // Dramatic gradient overlay
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.75)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Editorial typography overlay
                VStack(alignment: .leading, spacing: 12) {
                    // Micro label
                    Text(media.year.uppercased())
                        .font(.kuroMicro())
                        .tracking(2.0)
                        .foregroundColor(.white.opacity(0.7))

                    // Dramatic headline
                    Text(media.title.uppercased())
                        .font(.kuroFeature())
                        .tracking(0.8)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)

                    // Refined caption
                    if let genres = media.genres?.prefix(2) {
                        Text(genres.joined(separator: " · ").uppercased())
                            .font(.kuroCaption())
                            .tracking(1.8)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(EditorialLayout.marginEditorial)
                .allowsHitTesting(false)
            }
            .aspectRatio(EditorialLayout.heroAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 0))
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(KuroAnimation.editorial, value: isPressed)
        }
        .onTapGesture {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }
        .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }
}

// MARK: - Editorial Feature Card
// Medium size, elegant, refined
struct EditorialFeatureCard: View {
    let media: any MediaDisplayable
    @State private var isPressed = false
    @State private var showDetail = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image
            KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 700) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(EditorialLayout.standardAspectRatio, contentMode: .fill)
                        .clipped()
                case .failure, .empty:
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .aspectRatio(EditorialLayout.standardAspectRatio, contentMode: .fill)
                @unknown default:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 0))

            // Typography
            VStack(alignment: .leading, spacing: 6) {
                Text(media.year.uppercased())
                    .font(.kuroMicro())
                    .tracking(2.0)
                    .foregroundColor(.black.opacity(0.4))

                Text(media.title)
                    .font(.kuroTitle())
                    .tracking(0.3)
                    .foregroundColor(.black)
                    .lineLimit(2)

                if let genres = media.genres?.prefix(2) {
                    Text(genres.joined(separator: " · ").uppercased())
                        .font(.kuroCaption())
                        .tracking(1.6)
                        .foregroundColor(.black.opacity(0.5))
                }
            }
            .allowsHitTesting(false)
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(KuroAnimation.editorial, value: isPressed)
        .onTapGesture {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }
        .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }
}

// MARK: - Editorial Compact Card
// Small, refined, list-style
struct EditorialCompactCard: View {
    let media: any MediaDisplayable
    @State private var showDetail = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail
            KuroCachedAsyncImage(url: URL(string: media.imageURL ?? ""), maxPixelSize: 260) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 120)
                        .clipped()
                case .failure, .empty:
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(width: 80, height: 120)
                @unknown default:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 0))

            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text(media.year.uppercased())
                    .font(.kuroMicro())
                    .tracking(2.0)
                    .foregroundColor(.black.opacity(0.4))

                Text(media.title)
                    .font(.kuroBody())
                    .tracking(0.2)
                    .foregroundColor(.black)
                    .lineLimit(2)

                if let genres = media.genres?.prefix(2) {
                    Text(genres.joined(separator: " · ").uppercased())
                        .font(.kuroCaption())
                        .tracking(1.4)
                        .foregroundColor(.black.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)

            Spacer()
        }
        .frame(height: 120)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }
}

// MARK: - Editorial Grid Card
// Asymmetric grid item, magazine-style
struct EditorialGridCard: View {
    let media: any MediaDisplayable
    let size: GridSize
    @State private var isPressed = false
    @State private var showDetail = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    enum GridSize {
        case large
        case medium
        case small
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image
            KuroCachedAsyncImage(
                url: URL(string: media.imageURL ?? ""),
                maxPixelSize: size == .large ? 900 : (size == .medium ? 700 : 520)
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                case .failure, .empty:
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                @unknown default:
                    EmptyView()
                }
            }

            // Overlay for larger cards
            if size != .small {
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Typography
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title)
                        .font(size == .large ? .kuroHeadline() : .kuroBody())
                        .tracking(0.3)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.3), radius: 4)

                    Text(media.year.uppercased())
                        .font(.kuroMicro())
                        .tracking(1.8)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(size == .large ? 20 : 12)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(KuroAnimation.editorial, value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }
        .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }
}

// MARK: - Editorial List Row
// Minimal, refined list item
struct EditorialListRow: View {
    let media: any MediaDisplayable
    let number: Int?
    @State private var showDetail = false
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        HStack(spacing: 20) {
            // Optional number
            if let number = number {
                EditorialLayout.numberBadge(number)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(media.title)
                    .font(.kuroBody())
                    .tracking(0.2)
                    .foregroundColor(.black)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(media.year.uppercased())
                        .font(.kuroMicro())
                        .tracking(1.8)
                        .foregroundColor(.black.opacity(0.4))

                    if let genres = media.genres?.first {
                        Text("·")
                            .foregroundColor(.black.opacity(0.3))
                        Text(genres.uppercased())
                            .font(.kuroMicro())
                            .tracking(1.8)
                            .foregroundColor(.black.opacity(0.4))
                    }
                }
            }
            .allowsHitTesting(false)

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .light))
                .foregroundColor(.black.opacity(0.3))
                .allowsHitTesting(false)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        }
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: media.kind, id: media.id)
        }
    }
}
