import KuroCore
import SwiftUI
import UIKit

/// The one Home field: mountain when the shelf is empty (or nothing is in progress), the first
/// in-progress title's art when it is not.
/// Pinned behind the status bar and header on Home; the selected Anime/Manga word masks the same image.
struct HomePagePicture: View {
    @Environment(HomeStore.self) private var home
    var isActive: Bool = true
    var magnify: CGFloat = 1.7

    /// The first title in progress; a planned title never stands for the shelf.
    private var coverCard: HomeCard? {
        HomeShelfPolicy.leadCard(home.bundle?.active ?? [])
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if let card = coverCard {
                    titleArt(card)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    KuroSceneryLoop(tone: .neutralCanvas, isActive: isActive, magnify: magnify)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func titleArt(_ card: HomeCard) -> some View {
        if home.medium == "manga" {
            remoteFill(card.coverImage)
        } else {
            remoteFill(card.bannerImage ?? card.coverImage)
        }
    }

    @ViewBuilder
    private func remoteFill(_ raw: String?) -> some View {
        if let raw, let url = URL(string: raw) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 1200) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.kuroMissingArt
                }
            }
        } else {
            Color.kuroMissingArt
        }
    }
}

/// The selected medium word's fill (LANE_AMENDMENTS 7, PROTOTYPE_SPEC.md §4 / §8.9) for Home's lead
/// title: `KuroArtWordFill` over its cover. Without a title in progress the word takes the prototype's
/// own fill `#253a2a` (`.solid`); the invitation (an empty medium beside an occupied one) keeps its
/// mountain (`.mountain`, the page picture behind it).
struct HomePagePictureFill: View {
    enum Fallback { case solid, mountain }

    @Environment(HomeStore.self) private var home
    var fallback: Fallback = .solid

    /// The first title in progress; a planned title never stands for the shelf.
    private var coverCard: HomeCard? {
        HomeShelfPolicy.leadCard(home.bundle?.active ?? [])
    }

    var body: some View {
        KuroArtWordFill(raw: coverCard.map { $0.coverImage ?? $0.bannerImage ?? "" }, fallback: fallback)
    }
}

/// The medium word's artwork fill for one artwork (Home's lead title, the first story-card pick on Taste
/// and on the new-account Home): the artwork as it is, under the prototype's scrim
/// `linear-gradient(#15221c15, #15221c38)` on its `#253a2a` fallback.
///
/// Contrast floor (adaptive): when the band of the art the word shows is lighter on average than
/// `HomeMediumWordInk.targetLuma`, the whole fill is darkened by one uniform factor
/// (`HomeMediumWordInk.artMultiplier`) until it is not, so the selected word never reads lighter than
/// the unselected `#6e786f`. A uniform factor keeps the art's hue and range (the prototype's art stays
/// recognisable); art already dark enough is left as it is. `raw` nil: the solid `#253a2a`, or the
/// mountain.
struct KuroArtWordFill: View {
    let raw: String?
    var fallback: HomePagePictureFill.Fallback = .solid

    @Environment(\.displayScale) private var displayScale
    @State private var art: UIImage?
    @State private var multiplier: Double = 1

    var body: some View {
        if let raw {
            ZStack {
                HomeInk.switchUnlit
                if let art {
                    Image(uiImage: art)
                        .resizable()
                        .scaledToFill()
                    // Non-linear (sRGB) compositing: black at 1 − k scales every encoded channel by k.
                    Color.black.opacity(1 - multiplier)
                    // Highlights only: no channel lighter than the ceiling, so a white sky or page in
                    // the band never erases a stroke; darker and saturated art passes through.
                    HomeMediumWordInk.highlightCeiling.color.blendMode(.darken)
                }
                LinearGradient(colors: [HomeMediumWordInk.scrimTop, HomeMediumWordInk.scrimBottom],
                               startPoint: .top, endPoint: .bottom)
            }
            // Blend inside the fill only, never against what sits behind the word.
            .compositingGroup()
            .task(id: raw) { await load(raw) }
        } else if fallback == .mountain {
            Image("KuroZenMountains")
                .resizable()
                .scaledToFill()
                .scaleEffect(1.8, anchor: .bottom)
                .saturation(0.55)
        } else {
            HomeInk.switchUnlit
        }
    }

    /// The artwork from the shared pipeline (the same 800 pt bucket the other covers use), and the
    /// factor its word band needs.
    private func load(_ raw: String) async {
        guard let url = URL(string: raw), !raw.isEmpty else {
            art = nil
            multiplier = 1
            return
        }
        let image = await ImagePipeline.shared.image(url: url, maxPixelSize: 800 * max(1, Int(displayScale)))
        guard !Task.isCancelled else { return }
        multiplier = HomeMediumWordInk.artMultiplier(
            meanLuma: image?.cgImage.flatMap { HomeMediumWordInk.meanLuma(of: $0, wordAspect: HomeMediumWordInk.wordAspect) })
        art = image
    }
}

/// The prototype's Poster medium switch (PROTOTYPE_SPEC.md §4 "Medium switch"; LANE_AMENDMENTS 7),
/// shared by Home and Taste (Taste follows Home): two equal columns 12 pt apart over a 1 pt
/// `#20302744` hairline; heavy sans uppercase words (36 pt, 30 on small phones); the selected word
/// shows `fill` (the artwork, `KuroArtWordFill`) clipped into its letters with a 28 × 2 `#203027`
/// rule on the hairline; the other word is solid `#6e786f`. At accessibility sizes the words stack,
/// so each keeps the full width and neither is cut to "Ma…" (rulebook §4).
struct KuroPosterMediumSwitch<Fill: View>: View {
    let selection: MediaKind
    /// The content column's width (the word size follows it, never the screen).
    let contentWidth: CGFloat
    let onSelect: (MediaKind) -> Void
    let fill: Fill

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(selection: MediaKind, contentWidth: CGFloat, onSelect: @escaping (MediaKind) -> Void,
         @ViewBuilder fill: () -> Fill) {
        self.selection = selection
        self.contentWidth = contentWidth
        self.onSelect = onSelect
        self.fill = fill()
    }

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
        return layout {
            word(.anime, title: "Anime", stacked: stacked)
            word(.manga, title: "Manga", stacked: stacked)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(HomeInk.switchHairline).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private func word(_ value: MediaKind, title: String, stacked: Bool) -> some View {
        let selected = selection == value
        let size = KuroMediumSwitch.wordSize(for: .large, containerWidth: contentWidth)
        // The prototype's narrow phones (≤ 360) set the 30 pt word 4 pt lower in the same row, so the
        // words sit 19 pt above the rule there (17 at 36 pt).
        let wordTop: CGFloat = size < 36 ? 8 : 4
        let lettering = Text(title)
            .kuroMediumWordStyle(size: size)
            .lineLimit(1)
            // The single-word switch is the one place a scale factor is allowed (rulebook §4).
            .minimumScaleFactor(0.6)
        return Button {
            if !selected { KuroAccessibility.impactHaptic(.light); onSelect(value) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // The fill takes the word's own frame (an overlay), so the artwork never sizes the row.
                lettering
                    .foregroundStyle(selected ? Color.clear : HomeInk.switchUnselected)
                    .overlay {
                        if selected {
                            fill.mask(lettering)
                        }
                    }
                    .padding(.top, wordTop)
                Spacer(minLength: 4)
                // A fixed rule that fades in place on the hairline: it never travels between the words.
                // Its bottom row is the hairline's row (`ref-home-new-anime-390.png` rows 133–134 over
                // hairline row 134), so the two overlap into one 2 pt stroke.
                Rectangle()
                    .fill(HomeInk.switchMark)
                    .frame(width: 28, height: 2)
                    .opacity(selected ? 1 : 0)
            }
            // 58 pt from the top of the row to the hairline's foot (the 57 pt control plus the 1 pt the
            // rule shares with the hairline).
            .frame(maxWidth: .infinity, minHeight: stacked ? 53 : 58, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(title)
        .accessibilityHint(selected ? "" : KuroLocale.text("Shows your \(title.lowercased()).", "Zeigt deine \(title)-Titel."))
    }
}

/// The medium word's inks and its adaptive contrast floor (pure values, pinned by
/// `HomeAnimeLaneTests` and `HomeFirstRunRound2Tests`).
enum HomeMediumWordInk {
    /// The unselected word, `#6e786f` (sRGB luma about 0.455).
    nonisolated static let unselected = KuroRGB(0x6E / 255, 0x78 / 255, 0x6F / 255)
    /// The lightest mean sRGB luma (Rec. 601, 0…1) the word's art band may have before the scrim.
    /// The prototype's selected word reads about 92 / 255 against the unselected word's 128 (letter
    /// pixels in `ref-home-new-anime-390.png`), a gap of about 36 levels: at 0.33 a pale cover (the
    /// Your Name sky, a white manga page) lands there too, so the selected word stays the dark, heavy
    /// word of the pair. Art already darker passes through untouched.
    nonisolated static let targetLuma: Double = 0.33
    /// The lightest any channel of the art may be (`#8e938c`, luma about 0.57): a white sky or page in
    /// the band never reads lighter than the unselected word's lighter strokes, so no letter shows a
    /// pale patch, while saturated mid-tones keep their hue.
    nonisolated static let highlightCeiling = KuroRGB(0x8E / 255, 0x93 / 255, 0x8C / 255)
    /// The selected word's box is about three times as wide as it is tall (107 × 36 at 390).
    nonisolated static let wordAspect: Double = 3
    /// The prototype's scrim over the artwork: `#15221c15` → `#15221c38`.
    static let scrimTop = Color(hex: "15221C", opacity: Double(0x15) / 255)
    static let scrimBottom = Color(hex: "15221C", opacity: Double(0x38) / 255)

    /// The uniform factor for art whose word band has mean luma `meanLuma`: 1 for art at or below the
    /// target (or unknown), else the factor that brings the mean to the target.
    nonisolated static func artMultiplier(meanLuma: Double?) -> Double {
        guard let meanLuma, meanLuma > targetLuma else { return 1 }
        return targetLuma / meanLuma
    }

    /// Mean sRGB luma (0…1) of the centred band of `image` that a word `wordAspect` times as wide as it
    /// is tall shows (`scaledToFill`). Nil when the image cannot be read.
    nonisolated static func meanLuma(of image: CGImage, wordAspect: Double) -> Double? {
        let width = Double(image.width), height = Double(image.height)
        guard width > 0, height > 0, wordAspect > 0 else { return nil }
        let band: CGRect
        if width / height < wordAspect {
            let bandHeight = width / wordAspect
            band = CGRect(x: 0, y: (height - bandHeight) / 2, width: width, height: bandHeight)
        } else {
            let bandWidth = height * wordAspect
            band = CGRect(x: (width - bandWidth) / 2, y: 0, width: bandWidth, height: height)
        }
        guard let cropped = image.cropping(to: band.integral) else { return nil }
        let sampleWidth = 24, sampleHeight = 8
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: sampleWidth, height: sampleHeight,
                                          bitsPerComponent: 8, bytesPerRow: sampleWidth * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return true
        }
        guard drawn else { return nil }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.299 * Double(pixels[index]) + 0.587 * Double(pixels[index + 1]) + 0.114 * Double(pixels[index + 2])
        }
        return total / Double(sampleWidth * sampleHeight) / 255
    }
}
