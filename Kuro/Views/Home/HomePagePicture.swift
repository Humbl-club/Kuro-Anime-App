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
        if let card = coverCard {
            ZStack {
                HomeMediumWordInk.floor.color
                remote(card.coverImage ?? card.bannerImage).blendMode(.darken)
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
    private func remote(_ raw: String?) -> some View {
        if let raw, let url = URL(string: raw) {
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
