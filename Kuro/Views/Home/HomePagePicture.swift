import KuroCore
import SwiftUI

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

/// The selected medium word's fill (LANE_AMENDMENTS 7, PROTOTYPE_SPEC.md §4 / §8.9): the lead title's
/// artwork clipped into the letters, under the prototype's scrim `linear-gradient(#15221c15, #15221c38)`.
///
/// Contrast floor: no colour channel of the fill is lighter than `HomeMediumWordInk.floor`, which is
/// darker than the unselected word (`#6e786f`), so pale art never erases the selected word's strokes
/// and the selection never reads lighter than the other word. Darker art passes through untouched (a
/// per-channel darken toward ink, not a wash). The prototype paints the artwork's cover in the word
/// (`assets/anime1.jpg` for the anime lead), so both media use the cover.
///
/// Without a title in progress the word takes the prototype's own fill `#253a2a` (`.solid`); the empty
/// shelf keeps its mountain (`.mountain`, the invitation's picture).
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

/// The medium word's artwork fill for one artwork (Home's lead title, Taste's first pick): the cover
/// under the prototype's scrim, darkened per channel to `HomeMediumWordInk.floor` so it never reads
/// lighter than the unselected word. `raw` nil: the prototype's solid `#253a2a`, or the mountain.
struct KuroArtWordFill: View {
    let raw: String?
    var fallback: HomePagePictureFill.Fallback = .solid

    var body: some View {
        if let raw {
            ZStack {
                HomeMediumWordInk.floor.color
                remote(raw).blendMode(.darken)
                LinearGradient(colors: [HomeMediumWordInk.scrimTop, HomeMediumWordInk.scrimBottom],
                               startPoint: .top, endPoint: .bottom)
            }
            // Blend inside the fill only, never against what sits behind the word.
            .compositingGroup()
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

    @ViewBuilder
    private func remote(_ raw: String) -> some View {
        if let url = URL(string: raw), !raw.isEmpty {
            KuroCachedAsyncImage(url: url, maxPixelSize: 800) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    HomeInk.switchUnlit
                }
            }
        } else {
            HomeInk.switchUnlit
        }
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
                    .padding(.top, 4)
                Spacer(minLength: 4)
                // A fixed rule that fades in place on the hairline: it never travels between the words.
                Rectangle()
                    .fill(HomeInk.switchMark)
                    .frame(width: 28, height: 2)
                    .opacity(selected ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: stacked ? 52 : 56, alignment: .leading)
            .padding(.bottom, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(title)
        .accessibilityHint(selected ? "" : KuroLocale.text("Shows your \(title.lowercased()).", "Zeigt deine \(title)-Titel."))
    }
}

/// The medium word's inks (pure values, pinned by `HomeAnimeLaneTests`).
enum HomeMediumWordInk {
    /// The unselected word, `#6e786f`.
    static let unselected = KuroRGB(0x6E / 255, 0x78 / 255, 0x6F / 255)
    /// The art fill's ceiling: every channel of the selected word is at most this light. Darker than
    /// `unselected`, so the selected word is always at least as legible on the canvas.
    static let floor = KuroRGB(0x64 / 255, 0x6D / 255, 0x65 / 255)
    /// The prototype's scrim over the artwork: `#15221c15` → `#15221c38`.
    static let scrimTop = Color(hex: "15221C", opacity: Double(0x15) / 255)
    static let scrimBottom = Color(hex: "15221C", opacity: Double(0x38) / 255)
}
