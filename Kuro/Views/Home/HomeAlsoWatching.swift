import KuroCore
import SwiftUI

// MARK: - Also watching (prototype Poster Home, PROTOTYPE_SPEC.md §4 "Also watching")
// The titles in progress after the two scenes, in a 2-column grid (167 + 16 + 167 at 390; 139 with a
// 12 pt column gap at 320; one column at accessibility sizes so the key never meets the title).
//   heading   "Also watching" SF 15/21 w550 tracking −0.2 ink, "N titles" SF 10 muted; 25 above, 12 below
//   tile      poster 44 × 66 (radius 4, #e9e9e6, shadow 0 3 7 −4 #22222255, "S2" stamp #f3f4f4 with a
//             5 pt top-left corner) | 9 pt | title SF 12/15 w500 ink (3 lines), then "Ep." 10 pt #5b635c
//             + count 14 w500 over a 1 pt scrub (#d7d9d7 / #626962), then the title's material key
// No total is shown on a tile (the prototype hides `.progress-total` there).

/// One Also watching tile (dumb view; HomeView owns tracking and routes).
struct HomeAlsoWatchingTile<Key: View>: View {
    let title: String
    let posterURL: URL?
    let material: ArtworkMaterial
    let stamp: HomeSeasonTab?
    let readout: HomeProgressReadout
    let compact: Bool
    let onOpen: () -> Void
    @ViewBuilder let key: () -> Key

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The poster sits centred against the 92 pt column (the prototype's `align-items: center`).
        HStack(alignment: .center, spacing: compact ? 7 : 9) {
            Button(action: onOpen) {
                poster
            }
            .buttonStyle(HomeArtworkPressStyle())
            .accessibilityHidden(true) // The title button carries "Open <title>".
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onOpen) {
                    Text(title)
                        .font(.kuroCustom(compact ? 11 : 12, weight: .medium, relativeTo: .footnote, maxSize: 26))
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .lineLimit(HomeSceneMetrics.tileTitleLines(accessibility: dynamicTypeSize.isAccessibilitySize))
                        .fixedSize(horizontal: false, vertical: true)
                        // The prototype's 48 pt title row; a short title sits centred in it.
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KuroLocale.text("Open \(title)", "\(title) öffnen"))
                HStack(alignment: .center, spacing: 2) {
                    readoutView
                    key().frame(width: HomeSceneMetrics.keyColumn, height: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var poster: some View {
        HomeArtwork(url: posterURL, maxPixelSize: 300, placeholder: HomeInk.posterFill)
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(Double(0x0B) / 255), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                if let stamp {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        if stamp.word != nil {
                            Text("S").font(.kuroCustom(7, relativeTo: .caption2, maxSize: 12))
                        }
                        Text(stamp.number)
                            .font(.kuroCustom(stamp.word == nil ? 8 : 11, weight: .semibold, relativeTo: .caption1, maxSize: 16))
                            .monospacedDigit()
                    }
                    .foregroundStyle(HomeInk.tabInk)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(HomeInk.tabFace, in: UnevenRoundedRectangle(topLeadingRadius: 5))
                }
            }
            .shadow(color: Color(hex: "222222", opacity: Double(0x55) / 255), radius: 3, y: 2)
            .homeEntrance()
    }

    private var readoutView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(readout.unit)
                    .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(HomeInk.tileUnit)
                    .lineLimit(1)
                Text(readout.value)
                    .font(.kuroCustom(compact ? 13 : 14, weight: .medium, relativeTo: .subheadline, maxSize: 28))
                    .monospacedDigit()
                    .foregroundStyle(Color.kuroInk)
                    .lineLimit(1)
                    .kuroCountRoll(value: readout.value)
            }
            HomeScrub(fraction: readout.fraction, track: HomeInk.tileTrack, trace: HomeInk.tileTrace)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readout.spoken)
    }
}

/// The Also watching heading: "Also watching" and the real count of tiles.
struct HomeAlsoWatchingHeading: View {
    let count: Int
    let medium: MediaKind

    static func title(medium: MediaKind, german: Bool = KuroLocale.isGerman) -> String {
        switch (medium, german) {
        case (.anime, false): return "Also watching"
        case (.anime, true): return "Schaust du auch"
        case (.manga, false): return "Also reading"
        case (.manga, true): return "Liest du auch"
        }
    }

    static func countLine(_ count: Int, german: Bool = KuroLocale.isGerman) -> String {
        if german { return "\(count) Titel" }
        return count == 1 ? "1 title" : "\(count) titles"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Self.title(medium: medium))
                .font(.kuroCustom(15, weight: .semibold, relativeTo: .subheadline, maxSize: 30))
                .tracking(-0.2)
                .foregroundStyle(Color.kuroInk)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(Self.countLine(count))
                .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                .foregroundStyle(Color.kuroMuted)
        }
    }
}

/// The grid: two equal columns (one at accessibility sizes), rows 16 pt apart.
struct HomeAlsoWatchingGrid<Content: View>: View {
    let compact: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = HomeSceneMetrics.alsoWatchingColumns(accessibility: dynamicTypeSize.isAccessibilitySize)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: compact ? 12 : 16, alignment: .top),
                                 count: columns),
                  alignment: .leading, spacing: compact ? 14 : 16) {
            content()
        }
    }
}
