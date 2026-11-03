import SwiftUI

// MARK: - Branded tile (details-songs spec §5.2, D9; detail lane copy)
// One tile replaces every missing picture on the detail pages: the old kanji glyph placeholders, a missing
// source or adaptation cover, an episode without a (trusted) still, a person without a portrait. It
// never carries a kanji glyph, a stock face or a per-title colour table. Decorative: the row or card
// it sits in speaks. The songs + entities lane keeps an identical `EntityBrandedTile`; the integrator
// folds both into `Kuro/Views/Shared/KuroBrandedTile.swift` (§19.7).

/// kind: "Anime · TV", "Manga", "Light novel", "Ep. 8", "OP 1", "ED 2" (already localised); title optional.
struct DetailBrandedTile: View {
    enum Style { case paper, ink, onMaterial }
    let kind: String
    var title: String? = nil
    var initials: String? = nil      // people/studios: "YN"
    var style: Style = .paper
    var cornerRadius: CGFloat = 4
    /// Only for `.onMaterial` (the song art on the sound panel): the title's `base → deep`.
    var material: ArtworkMaterial? = nil

    /// The tile's title shows only from this width (§5.2: omitted when narrower than 60 pt).
    static let titleMinWidth: CGFloat = 60

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { box in
            ZStack(alignment: .topLeading) {
                switch style {
                case .paper:
                    paper(width: box.size.width)
                case .ink:
                    ink(size: box.size)
                case .onMaterial:
                    onMaterial
                }
            }
            .frame(width: box.size.width, height: box.size.height)
        }
        .clipShape(shape)
        .overlay {
            switch style {
            case .paper: shape.strokeBorder(Color(hex: "D9DEDB"), lineWidth: 1)
            case .ink: EmptyView()
            case .onMaterial: shape.strokeBorder(Color.white.opacity(Double(0x24) / 255), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    /// The prototype's D4 season tile: white → #EEF1EE at 150°, a faint 6 pt ruling, KURO and the kind
    /// word at the top, the title at the foot.
    private func paper(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color.white, Color(hex: "EEF1EE")],
                           startPoint: UnitPoint(x: 0.25, y: 0.07), endPoint: UnitPoint(x: 0.75, y: 0.93))
            DetailStripes(ink: Color(hex: "232C24", opacity: Double(0x05) / 255))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "KURO")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(1.4)
                Text(kind.uppercased())
                    .font(.system(size: 7))
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if let title = title?.detailNonEmpty, width >= Self.titleMinWidth {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "4F5A52"))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                }
            }
            .foregroundStyle(Color(hex: "7B847E"))
            .padding(width < 50 ? 5 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// People and studios without an image: the dark key gradient and the initials.
    private func ink(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color.kuroKeyDarkTop, Color.kuroKeyDarkBottom], startPoint: .top, endPoint: .bottom)
            if let initials = initials?.detailNonEmpty {
                Text(initials)
                    .font(.system(size: min(22, max(8, min(size.width, size.height) * 0.42)), weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var onMaterial: some View {
        ZStack {
            LinearGradient(colors: [material?.base.color ?? Color.kuroKeyDarkTop, material?.deep.color ?? Color.kuroKeyDarkBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 4) {
                Text(kind)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Rectangle().fill(Color.white.opacity(0.85)).frame(width: 14, height: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "Yuuki Aoi" → "YA"; nil when the name has no letters.
    nonisolated static func initials(of name: String?) -> String? {
        guard let name else { return nil }
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "·" }).filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first(where: { $0.isLetter }) }
        guard !letters.isEmpty else { return nil }
        return String(letters).uppercased()
    }
}
