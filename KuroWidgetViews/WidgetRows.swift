import KuroWidgetSupport
import SwiftUI
import UIKit

// MARK: - Shared widget pieces (spec §10.2, §10.3)
// Covers from the app-cached thumbnails (never fetched: no network in the extension), the paper
// branded tile for a missing cover (spec §5.2), the eyebrow, state messages, the row rule, the
// placeholder skeleton and the navigation-only link wrapper.

// MARK: Thumbnails

/// Where cover thumbnails are read from. The extension uses the App Group's `thumbs/`; KuroTests point
/// it at a fixture folder. A missing or unreadable file draws the branded tile.
nonisolated struct WidgetThumbnailSource: Sendable {
    private enum Mode: Sendable { case appGroup, directory(URL), none }
    private let mode: Mode

    static let appGroup = WidgetThumbnailSource(mode: .appGroup)
    static let none = WidgetThumbnailSource(mode: .none)
    static func directory(_ url: URL) -> WidgetThumbnailSource { WidgetThumbnailSource(mode: .directory(url)) }

    private init(mode: Mode) {
        self.mode = mode
    }

    /// The cached file for `name` (a validated name from the snapshot; `WidgetSnapshotStore` refuses
    /// anything that could leave `thumbs/`).
    func image(named name: String?) -> UIImage? {
        guard let name else { return nil }
        let store: WidgetSnapshotStore?
        switch mode {
        case .appGroup: store = WidgetSnapshotStore.shared()
        case .directory(let url): store = WidgetSnapshotStore(directory: url)
        case .none: store = nil
        }
        guard let url = store?.thumbnailURL(named: name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct WidgetThumbnailSourceKey: EnvironmentKey {
    static let defaultValue = WidgetThumbnailSource.appGroup
}

extension EnvironmentValues {
    /// The thumbnail folder the widget content reads (default: the App Group).
    var widgetThumbnails: WidgetThumbnailSource {
        get { self[WidgetThumbnailSourceKey.self] }
        set { self[WidgetThumbnailSourceKey.self] = newValue }
    }
}

/// A cover at a fixed size: the cached thumbnail, or the paper branded tile. Decorative.
struct WidgetCover: View {
    let name: String?
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 2
    @Environment(\.widgetThumbnails) private var thumbnails

    var body: some View {
        Group {
            if let image = thumbnails.image(named: name) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                WidgetBrandedTile(cornerRadius: cornerRadius)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The paper branded tile of spec §5.2 at widget size: the 150° white → #EEF1EE gradient, 1 pt
/// #D9DEDB border, 1 pt stripes every 6 pt and the "KURO" word when the tile is wide enough. No title
/// (narrower than 60 pt), no glyph, no per-title colour.
struct WidgetBrandedTile: View {
    var cornerRadius: CGFloat = 2

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [WidgetPalette.tileTop, WidgetPalette.tileBottom],
                               startPoint: UnitPoint(x: 0.25, y: 0.07), endPoint: UnitPoint(x: 0.75, y: 0.93))
                Path { path in
                    var x: CGFloat = 6
                    while x < proxy.size.width {
                        path.addRect(CGRect(x: x, y: 0, width: 1, height: proxy.size.height))
                        x += 6
                    }
                }
                .fill(WidgetPalette.tileStripe)
                if proxy.size.width >= 27 {
                    Text(verbatim: "KURO")
                        .font(.system(size: 7, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(WidgetPalette.tileWord)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.top, 4)
                        .padding(.leading, 3)
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(WidgetPalette.tileBorder, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: Text pieces

/// The eyebrow: 9 pt, tracking 1.05, uppercase, `HomeInk.kicker`. A heading for VoiceOver.
struct WidgetEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .regular))
            .tracking(1.05)
            .textCase(.uppercase)
            .foregroundStyle(WidgetPalette.kicker)
            .lineLimit(1)
            // "NÄCHSTES KAPITEL" beside the small widget's cover: tighten before truncating.
            .allowsTightening(true)
            .minimumScaleFactor(0.8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "No dates yet." / "Nothing in progress." under the eyebrow.
struct WidgetEmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .tracking(-0.2)
            .foregroundStyle(WidgetPalette.title)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The signed-out message, centred in the widget.
struct WidgetSignedOutMessage: View {
    let german: Bool

    var body: some View {
        Text(WidgetCopy.signedOut(german))
            .font(.system(size: 13, weight: .medium))
            .tracking(-0.2)
            .foregroundStyle(WidgetPalette.title)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The 1 pt #E3E7E1 rule between rows.
struct WidgetRule: View {
    var body: some View {
        Rectangle().fill(WidgetPalette.rule).frame(height: 1).accessibilityHidden(true)
    }
}

/// The gallery placeholder (`redactionReasons.contains(.placeholder)`): neutral bars and tiles, no
/// sample titles and no signed-out copy.
struct WidgetPlaceholder: View {
    let rows: Int
    let coverSize: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(WidgetPalette.rule).frame(width: 64, height: 6)
            ForEach(0..<max(1, rows), id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(WidgetPalette.rule)
                        .frame(width: coverSize.width, height: coverSize.height)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(WidgetPalette.rule).frame(maxWidth: 120).frame(height: 7)
                        Capsule().fill(WidgetPalette.rule.opacity(0.7)).frame(maxWidth: 80).frame(height: 6)
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// MARK: Navigation

/// Wraps `content` in a `Link` to the title journey when the row has one (navigation only, N10; a
/// write is never a URL). Small widgets ignore `Link`; they use `.widgetURL` instead.
struct WidgetLinked<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let url { Link(destination: url, label: content) } else { content() }
    }
}
