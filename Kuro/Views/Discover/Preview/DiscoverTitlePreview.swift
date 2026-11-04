import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - The long-press preview (spec 2026-11-04 §5.2)
// 300 pt wide, radius 14. The artwork: the banner at 2.2 : 1, or the cover at 2 : 3 capped at 260 pt
// tall on Home's poster fill. Under it the foot on the title's own `ArtworkMaterial` (base → deep,
// white text ≥ 7 : 1): the kicker ("ANIME · NEW TO YOU", 8 pt tracked 1.05), the title (17 semibold
// −0.35), the facts (10 pt), the synopsis (12 pt, 3 lines; the scrub line on the material while it
// loads, collapsed when the catalogue has none), a 1 pt white @ .14 rule and "Why it's here: …" (10 pt).
// Tapping the lifted preview only dismisses it (SwiftUI has no preview commit; D11): Open is the last
// menu item. The synopsis read is `CatalogStore.fetchAnimeById` / `fetchMangaById` (cached; it warms
// the detail page).

nonisolated enum DiscoverPreviewLayout {
    static let width: CGFloat = 300
    static let radius: CGFloat = 14
    static let bannerAspect: CGFloat = 2.2
    static let coverMaxHeight: CGFloat = 260

    /// The art window's height: the banner at 2.2 : 1, else the capped 2 : 3 cover.
    static func artHeight(hasBanner: Bool) -> CGFloat {
        hasBanner ? (width / bannerAspect).rounded() : coverMaxHeight
    }

    /// The cover's size inside the cover window (2 : 3 at the cap).
    static var coverSize: CGSize { CGSize(width: (coverMaxHeight * 2 / 3).rounded(), height: coverMaxHeight) }
}

struct DiscoverTitlePreview: View {
    let card: TasteCard
    /// The kicker's section words ("New to you"); nil: the medium only.
    let section: String?
    /// "Why it's here" reason text (already localized), if any.
    let reason: String?
    /// A synopsis the caller already has (renders); nil reads it from the catalogue.
    var knownSynopsis: String? = nil
    /// Called once when the preview appears (telemetry `discover_preview`).
    var onShown: () -> Void = {}

    @Environment(ArtworkMaterialStore.self) private var materials: ArtworkMaterialStore?
    @Environment(CatalogStore.self) private var catalog: CatalogStore?

    @State private var synopsis: String?
    @State private var synopsisLoaded = false

    private var german: Bool { KuroLocale.isGerman }

    private var material: ArtworkMaterial {
        let raw = card.bannerURL ?? card.media.imageURL
        return materials?.material(for: raw.flatMap { URL(string: $0) }, seedHex: nil) ?? .neutral
    }

    var body: some View {
        let material = material
        VStack(spacing: 0) {
            artwork
            foot
                .background(LinearGradient(colors: [material.base.color, material.deep.color],
                                           startPoint: .top, endPoint: .bottom))
        }
        .frame(width: DiscoverPreviewLayout.width)
        .clipShape(RoundedRectangle(cornerRadius: DiscoverPreviewLayout.radius, style: .continuous))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
        .onAppear(perform: onShown)
        .task(id: card.key) { await loadSynopsis() }
    }

    // MARK: Artwork

    @ViewBuilder
    private var artwork: some View {
        if let banner = card.bannerURL, let url = URL(string: banner) {
            HomeArtwork(url: url, maxPixelSize: 900, placeholder: HomeInk.posterFill)
                .frame(width: DiscoverPreviewLayout.width, height: DiscoverPreviewLayout.artHeight(hasBanner: true))
                .clipped()
                .accessibilityHidden(true)
        } else {
            let cover = DiscoverPreviewLayout.coverSize
            HomeInk.posterFill
                .frame(width: DiscoverPreviewLayout.width, height: DiscoverPreviewLayout.artHeight(hasBanner: false))
                .overlay {
                    HomeArtwork(url: card.media.imageURL.flatMap { URL(string: $0) }, maxPixelSize: 600,
                                placeholder: HomeInk.posterFill)
                        .frame(width: cover.width, height: cover.height)
                        .clipped()
                }
                .accessibilityHidden(true)
        }
    }

    // MARK: Foot

    private var foot: some View {
        let facts = DiscoverMenuCopy.previewFacts(kind: card.media.kind, year: card.media.year,
                                                  formatRaw: card.media.formatRaw, episodes: card.media.episodes,
                                                  chapters: card.media.chapters, statusRaw: card.media.statusRaw,
                                                  german: german)
        return VStack(alignment: .leading, spacing: 0) {
            Text(DiscoverMenuCopy.previewKicker(kind: card.media.kind, section: section, german: german))
                .font(.kuroCustom(8, weight: .semibold, relativeTo: .caption2, maxSize: 16))
                .tracking(1.05)
                .foregroundStyle(HomeInk.footSecondary)
                .lineLimit(1)
            Text(KuroCardText.sanitizeTitleForCard(card.media.title))
                .font(.kuroCustom(17, weight: .semibold, relativeTo: .headline, maxSize: 30))
                .tracking(-0.35)
                .foregroundStyle(HomeInk.footTitle)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let facts {
                Text(facts)
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 18))
                    .foregroundStyle(HomeInk.footFact)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            synopsisArea
            if let why = DiscoverMenuCopy.whyItsHere(reason, german: german) {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 1)
                    .padding(.top, 10)
                    .accessibilityHidden(true)
                Text(why)
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 18))
                    .foregroundStyle(HomeInk.footSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    /// Three lines reserved while the synopsis loads (a context-menu preview does not resize well after
    /// it appears); collapsed when the catalogue has none.
    @ViewBuilder
    private var synopsisArea: some View {
        let shown = knownSynopsis ?? synopsis
        if let shown {
            Text(shown)
                .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 20))
                .foregroundStyle(HomeInk.footTitle.opacity(0.92))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
        } else if !synopsisLoaded {
            Text(verbatim: "\n\n")
                .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 20))
                .hidden()
                .overlay(alignment: .topLeading) {
                    KuroScrubLine(tint: .white.opacity(0.5), track: .white.opacity(0.12))
                        .frame(maxWidth: 96)
                        .padding(.top, 6)
                }
                .padding(.top, 9)
                .accessibilityHidden(true)
        }
    }

    private func loadSynopsis() async {
        guard knownSynopsis == nil, !synopsisLoaded else { return }
        if let premise = card.premise, !premise.isEmpty {
            synopsis = premise
            synopsisLoaded = true
            return
        }
        guard let catalog else { synopsisLoaded = true; return }
        let text: String?
        switch card.media.kind {
        case .anime:
            let anime = try? await catalog.fetchAnimeById(card.media.id)
            text = anime.flatMap { $0.hasMeaningfulSynopsis ? $0.displayDescription : nil }
        case .manga:
            let manga = try? await catalog.fetchMangaById(card.media.id)
            text = manga.flatMap { $0.hasMeaningfulSynopsis ? $0.displayDescription : nil }
        }
        guard !Task.isCancelled else { return }
        synopsis = DiscoverTitlePreview.cleaned(text)
        synopsisLoaded = true
    }

    /// Whitespace-collapsed synopsis, nil when empty.
    nonisolated static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
