import SwiftUI

// MARK: - Widget palette (spec §10.2; HOME_GRAMMAR §1, §6)
// Compiled into BOTH the Kuro app target and the KuroWidgets extension (synchronized folder
// `KuroWidgetViews/`, spec D22). The extension cannot link the app's design system, so Home's values
// are copied here as literals (`kuroCanvasHome`, `kuroInk`, `kuroMuted`, `HomeInk.kicker`,
// `HomeInk.glanceInk`, the `.ink` key face of `KuroAdvanceKey`, the paper branded tile of spec §5.2).
// Never add a `Color(hex:)` extension here: the app already defines one.

nonisolated enum WidgetPalette {
    /// `#FFFEF8` (`kuroCanvasHome`): the widget canvas.
    static let canvas = rgb(0xFFFEF8)
    /// `#252625` (`kuroInk`).
    static let ink = rgb(0x252625)
    /// `#696C6B` (`kuroMuted`): secondary lines.
    static let muted = rgb(0x696C6B)
    /// `#666C68` (`HomeInk.kicker`): the eyebrow.
    static let kicker = rgb(0x666C68)
    /// `#303932` (`HomeInk.glanceInk`): titles.
    static let title = rgb(0x303932)
    /// `#E3E7E1`: the 1 pt rule between rows.
    static let rule = rgb(0xE3E7E1)

    // The `.ink` key face (`KuroKeyFace`, `kuroKeyDarkTop → kuroKeyDarkBottom`).
    static let keyTop = rgb(0x444A47)
    static let keyBottom = rgb(0x2C322F)
    static let keyInk = rgb(0xF8FAF7)
    /// `#20282326`: the raised key border.
    static let keyBorder = rgb(0x202823, alpha: Double(0x26) / 255)
    /// `inset 0 1px #ffffff35`.
    static let keyHighlight = Color.white.opacity(Double(0x35) / 255)
    /// `0 1px 2px #14231912`.
    static let keyDrop = rgb(0x142319, alpha: Double(0x12) / 255)
    /// The ghost ✓ on paper (`HomeInk.caughtUpOnPaper`).
    static let caughtUp = rgb(0x767B77)

    // Certainty mark (spec §5.3, paper style).
    static let markInk = rgb(0x4F5A52)
    static let markBorder = rgb(0x4F5A52, alpha: 0.35)
    static let estimateBorder = rgb(0x6B736C)

    // Paper branded tile (spec §5.2): a missing cover.
    static let tileTop = Color.white
    static let tileBottom = rgb(0xEEF1EE)
    static let tileBorder = rgb(0xD9DEDB)
    static let tileStripe = rgb(0x232C24, alpha: Double(0x05) / 255)
    static let tileWord = rgb(0x7B847E)

    /// `0xRRGGBB` as an sRGB colour.
    static func rgb(_ hex: UInt32, alpha: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: alpha)
    }
}
