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

struct DiscoverMoodKeys: View {
    let kind: MediaKind
    /// The "Like {title}" seed's title (nil: three keys).
    let likeTitle: String?
    let column: CGFloat
    let onOpen: (DiscoverMood) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var german: Bool { KuroLocale.isGerman }

    static let keyHeight: CGFloat = 56
    static let gap: CGFloat = 10

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
        VStack(alignment: .leading, spacing: 8) {
            Text(DiscoverIssueCopy.moodsEyebrow(german: german))
                .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(HomeInk.kicker)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap, alignment: .top), count: columns),
                      alignment: .leading, spacing: Self.gap) {
                ForEach(moods, id: \.self) { mood in
                    key(mood, compact: compact)
                }
            }
        }
    }

    /// In the compact column the words take two lines instead of truncating (288 pt, two columns).
    private func key(_ mood: DiscoverMood, compact: Bool) -> some View {
        let face = KuroKeyFace(style: .light)
        let title = DiscoverIssueCopy.moodTitle(mood, likeTitle: likeTitle, german: german)
        let subtitle = DiscoverIssueCopy.moodSubtitle(mood, german: german)
        return Button {
            KuroAccessibility.impactHaptic(.light)
            onOpen(mood)
        } label: {
            HStack(spacing: compact ? 8 : 10) {
                Image(systemName: DiscoverIssueCopy.moodSymbol(mood))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(face.ink)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 26))
                        .foregroundStyle(face.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : (compact ? 2 : 1))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(Color.kuroMuted)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : (compact ? 2 : 1))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Self.keyHeight, alignment: .leading)
            .background(
                LinearGradient(colors: [face.top, face.bottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: face.radius + 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: face.radius + 3, style: .continuous).strokeBorder(face.border, lineWidth: 1))
            .overlay(alignment: .top) {
                Rectangle().fill(face.highlight).frame(height: 1).padding(.horizontal, 8).padding(.top, 1)
            }
            .shadow(color: face.drop, radius: 1, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: face.radius + 3, style: .continuous))
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
