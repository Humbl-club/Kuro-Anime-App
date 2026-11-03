import SwiftUI

// MARK: - Branded tile (details-songs spec §5.2, D9; Songs + entities lane copy)
// One tile replaces every missing picture: a cover without an image, a person or studio without a photo,
// a song without (or veiled) artwork. The Detail lane writes `DetailBrandedTile` with identical values;
// the integrator folds both into `Kuro/Views/Shared/KuroBrandedTile.swift` (§19.7). It never carries a
// kanji glyph, a stock silhouette or a per-title colour table, and it is decorative: the row or card it
// sits in speaks (`accessibilityHidden(true)`).

struct EntityBrandedTile: View {
    enum Style: Equatable {
        /// Covers, stills, source and adaptation cards (the prototype's D4 season tile).
        case paper
        /// People and studios without an image.
        case ink
        /// Song art on the sound panel.
        case onMaterial(ArtworkMaterial)
    }

    /// "Anime · TV", "Manga", "OP 1", "Spoiler" (already localised).
    let kind: String
    var title: String? = nil
    /// People and studios: "YN".
    var initials: String? = nil
    var style: Style = .paper
    var cornerRadius: CGFloat = 4

    /// The paper tile's measured values (pinned in KuroTests).
    nonisolated enum Paper {
        static let fillTop = "FFFFFF"
        static let fillBottom = "EEF1EE"
        static let border = "D9DEDB"
        static let stripe = "232C24"
        static let stripeOpacity = Double(0x05) / 255
        static let stripeEvery: CGFloat = 6
        static let mark = "7B847E"
        static let titleInk = "4F5A52"
        /// Narrower than this, the title is left out.
        static let minTitleWidth: CGFloat = 60
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            switch style {
            case .paper: paper
            case .ink: ink
            case .onMaterial(let material): onMaterial(material)
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var paper: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: Paper.fillTop), Color(hex: Paper.fillBottom)],
                               startPoint: UnitPoint(x: 0.25, y: 0.07), endPoint: UnitPoint(x: 0.75, y: 0.93))
                Canvas { context, size in
                    var x: CGFloat = 0
                    while x < size.width {
                        context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                                     with: .color(Color(hex: Paper.stripe, opacity: Paper.stripeOpacity)))
                        x += Paper.stripeEvery
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("KURO")
                        .font(.system(size: 7, weight: .heavy))
                        .tracking(1.4)
                    Text(kind.uppercased())
                        .font(.system(size: 7))
                        .tracking(1)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let title, !title.isEmpty, proxy.size.width >= Paper.minTitleWidth {
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: Paper.titleInk))
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                    }
                }
                .foregroundStyle(Color(hex: Paper.mark))
                .padding(7)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .overlay(shape.strokeBorder(Color(hex: Paper.border), lineWidth: 1))
        }
    }

    private var ink: some View {
        ZStack {
            LinearGradient(colors: [.kuroKeyDarkTop, .kuroKeyDarkBottom], startPoint: .top, endPoint: .bottom)
            if let initials, !initials.isEmpty {
                Text(initials)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .minimumScaleFactor(0.5)
                    .padding(4)
            }
        }
    }

    private func onMaterial(_ material: ArtworkMaterial) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            LinearGradient(colors: [material.base.color, material.deep.color], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 4) {
                Text(kind)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Rectangle().fill(Color.white.opacity(0.85)).frame(width: 14, height: 1)
            }
            .padding(3)
        }
        .overlay(shape.strokeBorder(Color.white.opacity(Double(0x24) / 255), lineWidth: 1))
    }

    /// "Yuuki Kaji" → "YK"; one word → its first two letters; nil for nothing usable.
    nonisolated static func initials(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).filter { $0.first?.isLetter == true }
        if words.count >= 2, let first = words.first?.first, let last = words.last?.first {
            return String([first, last]).uppercased()
        }
        guard let word = words.first ?? name.split(separator: " ").first else { return nil }
        return String(word.prefix(2)).uppercased()
    }
}
