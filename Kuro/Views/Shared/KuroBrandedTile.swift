import SwiftUI

// MARK: - Branded tile (details-songs spec §5.2, D9)
// One tile replaces every missing picture: a cover without an image (the old 映 / 原作 glyphs), a source
// or adaptation card, an episode without a trusted still, a person or studio without a photo, a song
// without (or veiled) artwork. It never carries a kanji glyph, a stock silhouette or a per-title colour
// table, and it is decorative: the row or card it sits in speaks (`accessibilityHidden(true)`).
// Integrator fold (§19.7) of the lane copies `KuroBrandedTile` and `KuroBrandedTile`. Their paper
// values were identical; where they differed this keeps the entity copy's associated-value `Style`, its
// narrow rule (below 60 pt only "KURO", 4 pt padding, so 40 pt covers never break words) and its
// initials rule ("MAPPA" → "MA"), and the detail copy's ink initials sized to the tile.

struct KuroBrandedTile: View {
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
        /// Narrower than `minTitleWidth`, a kind word shows only up to this length (one line).
        static let narrowKindMaxCharacters = 5
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
                let roomy = proxy.size.width >= Paper.minTitleWidth
                VStack(alignment: .leading, spacing: 2) {
                    Text("KURO")
                        .font(.system(size: 7, weight: .heavy))
                        .tracking(1.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    // A narrow tile (a 40 pt quiet-row cover) carries the mark plus only a short kind
                    // word ("CH.", "EP. 8") on one line: words never break.
                    if !kind.isEmpty, roomy || kind.count <= Paper.narrowKindMaxCharacters {
                        Text(kind.uppercased())
                            .font(.system(size: 7))
                            .tracking(1)
                            .lineLimit(roomy ? 2 : 1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    if let title, !title.isEmpty, roomy {
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: Paper.titleInk))
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                    }
                }
                .foregroundStyle(Color(hex: Paper.mark))
                .padding(roomy ? 7 : 4)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .overlay(shape.strokeBorder(Color(hex: Paper.border), lineWidth: 1))
        }
    }

    private var ink: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [.kuroKeyDarkTop, .kuroKeyDarkBottom], startPoint: .top, endPoint: .bottom)
                if let initials, !initials.isEmpty {
                    Text(initials)
                        .font(.system(size: Self.initialsSize(proxy.size), weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(4)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The initials scale with the tile: 42 % of its short side, 8…22 pt.
    nonisolated static func initialsSize(_ size: CGSize) -> CGFloat {
        min(22, max(8, min(size.width, size.height) * 0.42))
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
