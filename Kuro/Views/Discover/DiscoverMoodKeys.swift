import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Mood keys (usability spec §5.4, D9)
// "IN THE MOOD FOR" (9 / 1.05), then a 2 × 2 grid, 10 pt gaps, each key 56 pt tall on the
// `KuroKeyFace(.light)` recipe, pressing with `HomeContactStyle` and a light haptic: a 15 pt symbol
// (timer, cup.and.saucer, bolt, heart), a 13 pt medium label and a 10 pt `kuroMuted` subtitle. The
// medium follows the issue (All and Anime: anime; Manga: manga). "Like {title}" shows only with a
// seed (the Library's latest well-rated Completed title); without one the grid keeps its shape with
// the last cell empty. At accessibility sizes, or a compact column with German, one column.
// A key opens the mood journey (a journey root, ✕ only; N3): the page calls
// `routes.openPage(DiscoverMoodRoute.journeyPage(...))` (lane B's `DiscoverMoodPage`, id `discover:mood:<raw>`).

struct DiscoverMoodPalette: Equatable {
    let topHex: String
    let bottomHex: String

    var top: Color { Color(hex: topHex) }
    var bottom: Color { Color(hex: bottomHex) }
}

struct DiscoverMoodKeys: View {
    let kind: MediaKind
    /// The "Like {title}" seed's title (nil: three keys).
    let likeTitle: String?
    /// Per-mood artwork URLs selected from renderable loaded pools (no duplicates).
    var moodArtwork: [DiscoverMood: String] = [:]
    let column: CGFloat
    var gutter: CGFloat = 0
    let onOpen: (DiscoverMood) -> Void

    init(
        kind: MediaKind,
        likeTitle: String?,
        moodArtwork: [DiscoverMood: String] = [:],
        column: CGFloat,
        gutter: CGFloat = 0,
        onOpen: @escaping (DiscoverMood) -> Void
    ) {
        self.kind = kind
        self.likeTitle = likeTitle
        self.moodArtwork = moodArtwork
        self.column = column
        self.gutter = gutter
        self.onOpen = onOpen
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var german: Bool { KuroLocale.isGerman }

    static let keyHeight: CGFloat = 56
    static let gap: CGFloat = 10
    static let tileWidth: CGFloat = 212
    static let tileHeight: CGFloat = 72

    /// Distinct cinematic two-stop palettes for each mood pill so cards read apart immediately.
    static func palette(for mood: DiscoverMood) -> DiscoverMoodPalette {
        switch mood {
        case .likeLastLoved: return DiscoverMoodPalette(topHex: "1A332E", bottomHex: "10201D")
        case .short: return DiscoverMoodPalette(topHex: "1E2B4A", bottomHex: "121A2E")
        case .cozy: return DiscoverMoodPalette(topHex: "422B1E", bottomHex: "291A12")
        case .intense: return DiscoverMoodPalette(topHex: "441B26", bottomHex: "280F16")
        case .action: return DiscoverMoodPalette(topHex: "422419", bottomHex: "26140E")
        case .heartfelt: return DiscoverMoodPalette(topHex: "402037", bottomHex: "261221")
        case .mindBending: return DiscoverMoodPalette(topHex: "2E2148", bottomHex: "1B132B")
        case .acclaimed: return DiscoverMoodPalette(topHex: "38301E", bottomHex: "221D12")
        }
    }

    /// Assigns each mood a unique renderable artwork URL from the current medium's loaded pools.
    static func selectArtwork(
        moods: [DiscoverMood],
        likeArtwork: String?,
        candidates: [(genres: [String], length: Int?, format: String?, score: Double?, art: String)]
    ) -> [DiscoverMood: String] {
        let valid = candidates.filter { ImagePipeline.hasRenderableArtwork($0.art) }
        var used: Set<String> = []
        var result: [DiscoverMood: String] = [:]

        func claim(_ candidate: String?) -> String? {
            guard let candidate, ImagePipeline.hasRenderableArtwork(candidate), used.insert(candidate).inserted else {
                return nil
            }
            return candidate
        }

        func firstUnused(matching predicate: ((genres: [String], length: Int?, format: String?, score: Double?, art: String)) -> Bool) -> String? {
            if let hit = valid.first(where: { !used.contains($0.art) && predicate($0) }) {
                return claim(hit.art)
            }
            return valid.first(where: { !used.contains($0.art) }).flatMap { claim($0.art) }
        }

        func hasAnyGenre(_ genres: [String], _ targets: [String]) -> Bool {
            let lowered = Set(genres.map { $0.lowercased() })
            return targets.contains { lowered.contains($0.lowercased()) }
        }

        for mood in moods {
            switch mood {
            case .likeLastLoved:
                result[mood] = claim(likeArtwork) ?? firstUnused { _ in true }
            case .short:
                result[mood] = firstUnused { c in
                    c.format?.uppercased() == "MOVIE" || (1...13).contains(c.length ?? 999)
                }
            case .cozy:
                result[mood] = firstUnused { hasAnyGenre($0.genres, ["Slice of Life", "Comedy"]) }
            case .intense:
                result[mood] = firstUnused { hasAnyGenre($0.genres, ["Thriller", "Mystery", "Horror"]) }
            case .action:
                result[mood] = firstUnused { hasAnyGenre($0.genres, ["Action", "Adventure"]) }
            case .heartfelt:
                result[mood] = firstUnused { hasAnyGenre($0.genres, ["Romance", "Drama"]) }
            case .mindBending:
                result[mood] = firstUnused { hasAnyGenre($0.genres, ["Psychological", "Sci-Fi", "Supernatural"]) }
            case .acclaimed:
                let top = valid
                    .filter { !used.contains($0.art) }
                    .max { ($0.score ?? -1) < ($1.score ?? -1) }
                result[mood] = claim(top?.art) ?? firstUnused { _ in true }
            }
        }
        return result
    }

    /// One column at accessibility sizes, or a compact column in German (long labels).
    static func columns(accessibility: Bool, compact: Bool, german: Bool) -> Int {
        accessibility || (compact && german) ? 1 : 2
    }

    /// The moods shown: the four, without "Like" when there is no seed.
    static func moods(hasSeed: Bool) -> [DiscoverMood] {
        hasSeed ? DiscoverMood.allCases : DiscoverMood.allCases.filter { $0 != .likeLastLoved }
    }

    var body: some View {
        let compact = DiscoverIssueLayout.isCompact(column: column)
        let columns = Self.columns(accessibility: dynamicTypeSize.isAccessibilitySize, compact: compact, german: german)
        let moods = Self.moods(hasSeed: likeTitle != nil)
        VStack(alignment: .leading, spacing: 10) {
            Text(DiscoverIssueCopy.moodsEyebrow(german: german))
                .font(.kuroCustom(15, weight: .semibold, relativeTo: .subheadline, maxSize: 28))
                .tracking(-0.2)
                .foregroundStyle(Color.kuroInk)
                .padding(.horizontal, gutter)
                .accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap, alignment: .top), count: columns),
                          alignment: .leading, spacing: Self.gap) {
                    ForEach(moods, id: \.self) { mood in
                        key(mood, compact: compact)
                    }
                }
                .padding(.horizontal, gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(moods, id: \.self) { mood in
                            compactPill(mood)
                        }
                    }
                    .padding(.horizontal, gutter)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .kuroSwipeExclusionZone()
            }
        }
    }

    private func compactPill(_ mood: DiscoverMood) -> some View {
        let title = DiscoverIssueCopy.moodTitle(mood, likeTitle: likeTitle, german: german)
        let subtitle = DiscoverIssueCopy.moodSubtitle(mood, german: german)
        let palette = Self.palette(for: mood)
        let artwork = moodArtwork[mood]
        return Button {
            KuroAccessibility.impactHaptic(.light)
            onOpen(mood)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                    Circle()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5)
                    Image(systemName: DiscoverIssueCopy.moodSymbol(mood))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kuroCustom(13.5, weight: .semibold, relativeTo: .footnote, maxSize: 22))
                        .tracking(-0.2)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.kuroCustom(11, relativeTo: .caption2, maxSize: 18))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: Self.tileWidth, height: Self.tileHeight, alignment: .leading)
            .background {
                KuroBlurredArtworkFill(
                    raw: artwork,
                    top: palette.top,
                    bottom: palette.bottom,
                    leadingScrim: 0.68,
                    trailingScrim: 0.36
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: palette.bottom.opacity(0.22), radius: 6, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    /// In the compact column the words take two lines instead of truncating (288 pt, two columns).
    private func key(_ mood: DiscoverMood, compact: Bool) -> some View {
        let title = DiscoverIssueCopy.moodTitle(mood, likeTitle: likeTitle, german: german)
        let subtitle = DiscoverIssueCopy.moodSubtitle(mood, german: german)
        let palette = Self.palette(for: mood)
        let artwork = moodArtwork[mood]
        return Button {
            KuroAccessibility.impactHaptic(.light)
            onOpen(mood)
        } label: {
            HStack(spacing: compact ? 8 : 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                    Circle()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5)
                    Image(systemName: DiscoverIssueCopy.moodSymbol(mood))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kuroCustom(13.5, weight: .semibold, relativeTo: .footnote, maxSize: 26))
                        .foregroundStyle(Color.white)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : (compact ? 2 : 1))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.kuroCustom(10.5, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(Color.white.opacity(0.82))
                        // Two lines at every size (a German subtitle is never cut); the key grows.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: Self.keyHeight, alignment: .leading)
            .background {
                KuroBlurredArtworkFill(
                    raw: artwork,
                    top: palette.top,
                    bottom: palette.bottom,
                    leadingScrim: 0.68,
                    trailingScrim: 0.36
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: palette.bottom.opacity(0.22), radius: 6, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
