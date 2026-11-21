import KuroCore
import SwiftUI

// MARK: - "Your year" (details-songs spec §12.3; Home's scene card, G§8.3)
// A small scene card in the "most time" title's artwork material (banner first, then cover), or the
// neutral material when no title has a known length:
//   artwork window  3.25 : 1, top corners 5, with Home's season tab "YEAR" + the year (17 semibold mono);
//                   drawn only when the title has artwork (no blank window)
//   material foot   "{n} titles this year", 17 semibold −0.35 #fafafa, min 58
//   fact rows       1 pt white @ 0x0D top rule, 10 pt #dce2df: "saved or changed · completed", then
//                   "Most time: {title} ›" (its own button, pushes that title)
// Then the honest note (Kuro records no finish date). The card itself is not a button.

struct ProfileYearCard: View {
    let year: ProfileStats.Year
    let onOpen: (MediaKey) -> Void

    @Environment(ArtworkMaterialStore.self) private var materials
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        let artwork = year.mostTime?.artwork
        let hasArtwork = artwork != nil
        let material = artwork.map { materials.material(for: $0, seedHex: nil) } ?? .neutral
        let lightSurface = !hasArtwork
        let cardShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if let artwork {
                        ZStack(alignment: .bottomLeading) {
                            Color.clear
                                .aspectRatio(HomeSceneMetrics.artworkAspect, contentMode: .fit)
                                .overlay { HomeArtwork(url: artwork, maxPixelSize: 1200, placeholder: material.base.color) }
                                .clipped()
                                .overlay {
                                    LinearGradient(colors: [.clear, Color.black.opacity(0.18)], startPoint: .center, endPoint: .bottom)
                                }
                                .accessibilityHidden(true)
                            yearTab.padding(.leading, 12)
                        }
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous))
                    }
                    foot(showsYear: !hasArtwork, onLight: lightSurface)
                    factRow(Self.factLine(year, german: german), onLight: lightSurface)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ProfileStatsCopy.yearSpoken(year, german: german))

                if let most = year.mostTime {
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        onOpen(most.key)
                    } label: {
                        HStack(spacing: 5) {
                            Text(ProfileStatsCopy.mostTime(most.title, german: german))
                                .lineLimit(1)
                            Text("›").accessibilityHidden(true)
                        }
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 22))
                        .foregroundStyle(lightSurface ? Color.kuroInkSecondary : HomeInk.footFact)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeContactStyle())
                    .padding(.horizontal, 14)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(lightSurface ? Color.kuroHairline : Color.white.opacity(Double(0x0D) / 255))
                            .frame(height: lightSurface ? 0.5 : 1)
                    }
                    .accessibilityLabel(ProfileStatsCopy.mostTime(most.title, german: german))
                    .accessibilityHint(KuroLocale.text("Opens the title", "Öffnet den Titel"))
                }
            }
            .background {
                if lightSurface {
                    Color.white
                } else {
                    LinearGradient(colors: [material.base.color, material.deep.color],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipShape(cardShape)
            .overlay {
                if lightSurface {
                    cardShape.strokeBorder(HomeInk.glanceBorder, lineWidth: 1)
                }
            }
            .shadow(color: lightSurface ? HomeInk.glanceShadow : Color.black.opacity(0.06), radius: 2, y: 1)
            .animation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.medium : nil, value: material)

            Text(ProfileStatsCopy.yearNote(year.year, german: german))
                .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 22))
                .foregroundStyle(Color.kuroMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "saved or changed · k of them now completed" (the completed part only when k > 0).
    static func factLine(_ year: ProfileStats.Year, german: Bool) -> String {
        var parts = [ProfileStatsCopy.savedOrChanged(year.titles, german: german)]
        if year.completed > 0 { parts.append(ProfileStatsCopy.completed(year.completed, german: german)) }
        return parts.joined(separator: " · ")
    }

    private var yearTab: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            Text(ProfileStatsCopy.yearTab(german: german))
                .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 14))
                .tracking(0.3)
                .textCase(.uppercase)
            Text(String(year.year))
                .font(.kuroCustom(17, weight: .semibold, relativeTo: .headline, maxSize: 28))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(HomeInk.tabInk)
        .padding(.horizontal, 8)
        .frame(minHeight: 31)
        .fixedSize(horizontal: false, vertical: true)
        .background(HomeInk.tabFace, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous))
    }

    private func foot(showsYear: Bool, onLight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsYear {
                Text("\(ProfileStatsCopy.yearTab(german: german)) \(String(year.year))")
                    .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                    .tracking(1.05)
                    .textCase(.uppercase)
                    .foregroundStyle(onLight ? HomeInk.kicker : Color(hex: "C6CECA"))
            }
            Text(ProfileStatsCopy.yearTitle(year.titles, german: german))
                .font(.kuroCustom(17, weight: .semibold, relativeTo: .headline, maxSize: 34))
                .tracking(-0.35)
                .foregroundStyle(onLight ? Color.kuroInk : HomeInk.footTitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(onLight ? Color.kuroHairline : Color.white.opacity(Double(0x18) / 255))
                .frame(height: onLight ? 0.5 : 1)
        }
    }

    private func factRow(_ text: String, onLight: Bool) -> some View {
        Text(text)
            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 22))
            .foregroundStyle(onLight ? Color.kuroInkSecondary : HomeInk.footFact)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, 14)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(onLight ? Color.kuroHairline : Color.white.opacity(Double(0x0D) / 255))
                    .frame(height: onLight ? 0.5 : 1)
            }
    }
}
