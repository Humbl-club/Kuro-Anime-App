import KuroCore
import SwiftUI

// MARK: - Advance key (spec §3.5, rulebook §7; prototype raised keys, PROTOTYPE_SPEC.md §2, §3.3)
// The +1 key: a 44×44 pt target, a sibling of the title's detail target (never nested inside it).
// The prototype draws a raised face inset inside the target:
//   light     34 pt face, radius 7, `kuroKeyLightTop → kuroKeyLightBottom`, ink #29352c
//             (Anime scene foot on art)
//   dark      38 pt face, radius 6, solid #2b342e with a #2b342e border, ink #f8faf7 (Manga leaf)
//   ink       34 pt face, radius 7, `kuroKeyDarkTop → kuroKeyDarkBottom` (#444a47 → #2c322f), ink
//             #f8faf7: the CSS `--key-face` dark for keys without artwork (Folio)
//   material  34 pt face, radius 7, the title's artwork `base → deep`, white ink (Also watching,
//             the detail "Up next" key)
// Light, ink and material faces: 1 pt #20282326 border, inset 0 1 white highlight, 0 1 2 drop shadow.
// Pressed (120 ms contact): face scale 0.95, darkened to 86 %, inset 0 2 3 shadow.
// Glyph: `plus`; `checkmark` when caught up (disabled); `list.number` when the next unit needs a
// choice. A selection tick on tap; the caller fires the success haptic only after the durable accept
// and then changes `confirmTrigger`: the face settles (160 ms), the ✓ cap stamps in (`confirm`) and
// the + cap returns (`restore`). A caught-up key shows neither (the prototype disables it).

struct KuroAdvanceKey: View {
    enum Style: Equatable {
        case light
        /// The manga leaf key: a solid #2b342e face.
        case dark
        /// The prototype's dark gradient key for keys without an artwork material (Folio).
        case ink
        /// A face cut from the title's artwork material.
        case material(ArtworkMaterial)
    }

    enum Phase: Equatable {
        /// Tapping advances by one unit.
        case advance
        /// Caught up: nothing to advance (disabled, checkmark).
        case caughtUp
        /// The next unit needs a choice (opens the caller's chooser).
        case needsChoice
        /// A write for this title is in flight (disabled, dimmed glyph).
        case pending
    }

    let style: Style
    var phase: Phase = .advance
    /// Full VoiceOver label, e.g. `KuroAdvanceCopy.label(...)`: "Mark episode 8 of Cowboy Bebop watched".
    let accessibilityText: String
    /// Change after a durable save to play the prototype's confirm / restore stamp. 0 = never saved.
    var confirmTrigger: Int = 0
    let action: () -> Void

    init(style: Style, phase: Phase = .advance, accessibilityText: String, confirmTrigger: Int = 0,
         action: @escaping () -> Void) {
        self.style = style
        self.phase = phase
        self.accessibilityText = accessibilityText
        self.confirmTrigger = confirmTrigger
        self.action = action
    }

    private var glyph: String {
        switch phase {
        case .advance, .pending: return "plus"
        case .caughtUp: return "checkmark"
        case .needsChoice: return "list.number"
        }
    }

    private var isInteractive: Bool { phase == .advance || phase == .needsChoice }

    private var glyphFont: Font { .kuroCustom(15, weight: .regular, relativeTo: .body, maxSize: 22) }

    var body: some View {
        let face = KuroKeyFace(style: style)
        Button {
            guard isInteractive else { return }
            KuroAccessibility.selectionHaptic()
            action()
        } label: {
            ZStack {
                // A caught-up key plays neither confirm nor restore (the prototype disables it): its
                // glyph is a separate view, so returning to advance mounts fresh and does not animate.
                if phase == .caughtUp {
                    Image(systemName: glyph)
                        .font(glyphFont)
                } else {
                    Image(systemName: glyph)
                        .font(glyphFont)
                        .opacity(phase == .pending ? 0.4 : 1)
                        .kuroRestore(trigger: confirmTrigger)
                    Image(systemName: "checkmark")
                        .font(glyphFont)
                        .kuroConfirmStamp(trigger: confirmTrigger)
                }
            }
            .foregroundStyle(face.ink)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroAdvanceKeyStyle(face: face, settleTrigger: confirmTrigger, settles: phase != .caughtUp))
        .disabled(!isInteractive)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(phase == .caughtUp ? KuroLocale.text("Caught up", "Auf dem neuesten Stand")
                            : phase == .pending ? KuroLocale.text("Saving", "Wird gespeichert") : "")
    }
}

/// The raised face of one key style (measured values from PROTOTYPE_SPEC.md §2 / §3.3 / §4).
struct KuroKeyFace {
    let size: CGFloat
    let radius: CGFloat
    let top: Color
    let bottom: Color
    let border: Color
    let highlight: Color
    let drop: Color
    let ink: Color

    /// `#20282326`: the light and material key border.
    private static let raisedBorder = Color(hex: "202823", opacity: Double(0x26) / 255)
    /// `inset 0 1px #ffffff35` (light / material) and `#ffffff1f` (manga leaf).
    private static let raisedHighlight = Color.white.opacity(Double(0x35) / 255)
    /// `0 1px 2px #14231912` (light / material) and `#28372a14` (manga leaf).
    private static let raisedDrop = Color(hex: "142319", opacity: Double(0x12) / 255)
    /// The manga leaf key (`--mp-key`).
    private static let leaf = Color(hex: "2B342E")
    /// Pressed: `inset 0 2px 3px #151d2430`.
    static let pressedInset = Color(hex: "151D24", opacity: Double(0x30) / 255)

    init(style: KuroAdvanceKey.Style) {
        switch style {
        case .light:
            size = 34; radius = 7
            top = .kuroKeyLightTop; bottom = .kuroKeyLightBottom
            border = Self.raisedBorder; highlight = Self.raisedHighlight; drop = Self.raisedDrop
            ink = Color(hex: "29352C")
        case .dark:
            size = 38; radius = 6
            top = Self.leaf; bottom = Self.leaf
            border = Self.leaf; highlight = Color.white.opacity(Double(0x1F) / 255)
            drop = Color(hex: "28372A", opacity: Double(0x14) / 255)
            ink = Color(hex: "F8FAF7")
        case .ink:
            size = 34; radius = 7
            top = .kuroKeyDarkTop; bottom = .kuroKeyDarkBottom
            border = Self.raisedBorder; highlight = Self.raisedHighlight; drop = Self.raisedDrop
            ink = Color(hex: "F8FAF7")
        case .material(let material):
            size = 34; radius = 7
            top = material.base.color; bottom = material.deep.color
            border = Self.raisedBorder; highlight = Self.raisedHighlight; drop = Self.raisedDrop
            ink = material.ink.color
        }
    }
}

private struct KuroAdvanceKeyStyle: ButtonStyle {
    let face: KuroKeyFace
    let settleTrigger: Int
    /// False on a caught-up key: no settle, and returning to advance mounts a fresh animator.
    let settles: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: face.radius, style: .continuous)
        let gradient = LinearGradient(colors: [face.top, face.bottom], startPoint: .top, endPoint: .bottom)
        let fill: AnyShapeStyle = pressed
            ? AnyShapeStyle(gradient.shadow(.inner(color: KuroKeyFace.pressedInset, radius: 1.5, x: 0, y: 2)))
            : AnyShapeStyle(gradient.shadow(.inner(color: face.highlight, radius: 0, x: 0, y: 1)))
        let faceView = shape
            .fill(fill)
            .overlay(shape.fill(Color.black.opacity(pressed ? 0.14 : 0)))
            .overlay(shape.strokeBorder(face.border, lineWidth: 1))
            .shadow(color: pressed ? .clear : face.drop, radius: 1, x: 0, y: 1)
            .frame(width: face.size, height: face.size)
            .scaleEffect(pressed ? 0.95 : 1)
        return configuration.label
            .background {
                if settles {
                    faceView.kuroPressSettle(trigger: settleTrigger)
                } else {
                    faceView
                }
            }
            .kuroAnimation(KuroMotion.contact, value: pressed)
    }
}

/// EN/DE VoiceOver copy for the advance key (pure; rulebook §12).
nonisolated enum KuroAdvanceCopy {
    /// "Mark episode 8 of Cowboy Bebop watched, 7 of 26" /
    /// "Folge 8 von Cowboy Bebop als gesehen markieren, 7 von 26".
    /// `current`/`total` add the position when known; an unknown total is omitted, never 0.
    static func label(medium: MediaKind, nextUnit: Int, title: String?, current: Int? = nil,
                      total: Int? = nil, german: Bool) -> String {
        let unit: String
        let verb: String
        switch (medium, german) {
        case (.anime, false): unit = "episode \(nextUnit)"; verb = "watched"
        case (.manga, false): unit = "chapter \(nextUnit)"; verb = "read"
        case (.anime, true): unit = "Folge \(nextUnit)"; verb = "als gesehen markieren"
        case (.manga, true): unit = "Kapitel \(nextUnit)"; verb = "als gelesen markieren"
        }
        let name = trimmedName(title)
        var text: String
        if german {
            text = name.map { "\(unit) von \($0) \(verb)" } ?? "\(unit) \(verb)"
        } else {
            text = name.map { "Mark \(unit) of \($0) \(verb)" } ?? "Mark \(unit) \(verb)"
        }
        if let current {
            if let total, total > 0 {
                text += german ? ", \(current) von \(total)" : ", \(current) of \(total)"
            } else {
                text += german ? ", bei \(current)" : ", at \(current)"
            }
        }
        return text
    }

    /// "Caught up on Cowboy Bebop" / "Bei Cowboy Bebop auf dem neuesten Stand".
    static func caughtUpLabel(title: String?, german: Bool) -> String {
        guard let name = trimmedName(title) else {
            return german ? "Auf dem neuesten Stand" : "Caught up"
        }
        return german ? "Bei \(name) auf dem neuesten Stand" : "Caught up on \(name)"
    }

    private static func trimmedName(_ title: String?) -> String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
