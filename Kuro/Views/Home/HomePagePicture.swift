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

/// Letter-mask crop of the same Home picture (ridge for empty, first title for populated).
///
/// Title art gets a contrast floor: no colour channel of the fill is lighter than `kuroInkSecondary`
/// (about 6.7:1 on paper, darker than the unselected word's `kuroInkQuiet`), so pale art never erases
/// the selected word's strokes and the selection never reads lighter than the other word. Darker art
/// passes through untouched (a per-channel darken, not a wash). The mountain keeps its own treatment.
struct HomePagePictureFill: View {
    @Environment(HomeStore.self) private var home

    /// The first title in progress; a planned title never stands for the shelf.
    private var coverCard: HomeCard? {
        HomeShelfPolicy.leadCard(home.bundle?.active ?? [])
    }

    var body: some View {
        if let card = coverCard {
            ZStack {
                Color.kuroInkSecondary
                titleArt(card).blendMode(.darken)
            }
            // Blend inside the fill only, never against what sits behind the word.
            .compositingGroup()
        } else {
            Image("KuroZenMountains")
                .resizable()
                .scaledToFill()
                .scaleEffect(1.8, anchor: .bottom)
                .saturation(0.55)
        }
    }

    @ViewBuilder
    private func titleArt(_ card: HomeCard) -> some View {
        if home.medium == "manga" {
            remote(card.coverImage)
        } else {
            remote(card.bannerImage ?? card.coverImage)
        }
    }

    @ViewBuilder
    private func remote(_ raw: String?) -> some View {
        if let raw, let url = URL(string: raw) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 800) { phase in
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
