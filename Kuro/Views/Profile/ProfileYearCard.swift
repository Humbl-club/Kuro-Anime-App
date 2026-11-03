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
        let material = artwork.map { materials.material(for: $0, seedHex: nil) } ?? .neutral
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
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5))
                    }
                    foot(showsYear: artwork == nil)
                    factRow(Self.factLine(year, german: german))
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
                        .foregroundStyle(HomeInk.footFact)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeContactStyle())
                    .padding(.horizontal, 14)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x0D) / 255)).frame(height: 1) }
                    .accessibilityLabel(ProfileStatsCopy.mostTime(most.title, german: german))
                    .accessibilityHint(KuroLocale.text("Opens the title", "Öffnet den Titel"))
                }
            }
            .background(LinearGradient(colors: [material.base.color, material.deep.color],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: Color(hex: "19221B", opacity: Double(0x0A) / 255), radius: 1, y: 1)
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
        .background(HomeInk.tabFace, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
    }

    private func foot(showsYear: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsYear {
                Text("\(ProfileStatsCopy.yearTab(german: german)) \(String(year.year))")
                    .font(.kuroCustom(8, relativeTo: .caption2, maxSize: 16))
                    .tracking(1.7)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(hex: "C6CECA"))
            }
            Text(ProfileStatsCopy.yearTitle(year.titles, german: german))
                .font(.kuroCustom(17, weight: .semibold, relativeTo: .headline, maxSize: 34))
                .tracking(-0.35)
                .foregroundStyle(HomeInk.footTitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x18) / 255)).frame(height: 1) }
    }

    private func factRow(_ text: String) -> some View {
        Text(text)
            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 22))
            .foregroundStyle(HomeInk.footFact)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, 14)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x0D) / 255)).frame(height: 1) }
    }
}
