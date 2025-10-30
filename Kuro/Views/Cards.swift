import SwiftUI

// MARK: - Shared Horizontal Anime Card
public struct SharedHorizontalAnimeCard: View {
    let anime: Anime
    let width: CGFloat
    let height: CGFloat
    let showBadge: Bool
    let tap: () -> Void

    public init(anime: Anime, width: CGFloat, height: CGFloat, showBadge: Bool = true, tap: @escaping () -> Void) {
        self.anime = anime
        self.width = width
        self.height = height
        self.showBadge = showBadge
        self.tap = tap
    }

    public var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: anime.coverImageLarge ?? anime.coverImageMedium ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.04))
                        .overlay(ProgressView().scaleEffect(0.6))
                }
                .frame(width: width, height: height)
                .clipped()
                .cornerRadius(4)
                .overlay(
                    Group {
                        if showBadge, let score = anime.averageScore {
                            VStack {
                                HStack {
                                    Spacer()
                                    HStack(spacing: 2) {
                                        Text("★").font(.system(size: 8))
                                        Text(String(format: "%.1f", Double(score) / 10.0))
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                                    .padding(6)
                                }
                                Spacer()
                            }
                        }
                    }
                )

                Text(anime.displayTitle.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.3)
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .frame(width: width, alignment: .leading)

                if let year = anime.seasonYear {
                    Text("\(year)")
                        .font(.system(size: 9, weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.black.opacity(0.4))
                }
            }
            .transaction { $0.animation = nil }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Shared Vertical Anime Card
public struct SharedVerticalAnimeCard: View {
    let anime: Anime
    let showBadge: Bool
    let tap: () -> Void

    public init(anime: Anime, showBadge: Bool = true, tap: @escaping () -> Void) {
        self.anime = anime
        self.showBadge = showBadge
        self.tap = tap
    }

    public var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: anime.coverImageLarge ?? anime.coverImageMedium ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.04))
                        .overlay(ProgressView().scaleEffect(0.6))
                }
                .aspectRatio(2/3, contentMode: .fill)
                .clipped()
                .cornerRadius(4)
                .overlay(
                    Group {
                        if showBadge, let score = anime.averageScore {
                            VStack {
                                HStack {
                                    Spacer()
                                    HStack(spacing: 2) {
                                        Text("★").font(.system(size: 8))
                                        Text(String(format: "%.1f", Double(score) / 10.0))
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                                    .padding(6)
                                }
                                Spacer()
                            }
                        }
                    }
                )

                Text(anime.displayTitle.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.3)
                    .foregroundColor(.black)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if let year = anime.seasonYear {
                        Text("\(year)")
                            .font(.system(size: 9, weight: .light))
                            .foregroundColor(.black.opacity(0.4))
                    }
                    if let episodes = anime.episodeCount {
                        Text("·").foregroundColor(.black.opacity(0.3))
                        Text("\(episodes) EP")
                            .font(.system(size: 9, weight: .light))
                            .foregroundColor(.black.opacity(0.4))
                    }
                }
            }
            .transaction { $0.animation = nil }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
