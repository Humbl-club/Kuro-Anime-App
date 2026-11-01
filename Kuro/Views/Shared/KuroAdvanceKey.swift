import KuroCore
import SwiftUI

// MARK: - Advance key (spec §3.5, rulebook §7)
// The +1 key: 44×44 pt, a sibling of the title's detail target (never nested inside it).
//   light  white face, black-12% inset rim, ink glyph (Anime scene foot)
//   dark   ink face, white-18% inset rim, white glyph (Manga cover)
// Corner radius 5 pt outside, 4 pt for the inset rim. Glyph: `plus`; `checkmark` when caught up
// (disabled); `list.number` when the next unit needs a choice. A selection tick on tap; the caller
// fires the success haptic only after the durable accept.

struct KuroAdvanceKey: View {
    enum Style {
        case light
        case dark
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
    let action: () -> Void

    init(style: Style, phase: Phase = .advance, accessibilityText: String, action: @escaping () -> Void) {
        self.style = style
        self.phase = phase
        self.accessibilityText = accessibilityText
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

    var body: some View {
        Button {
            guard isInteractive else { return }
            KuroAccessibility.selectionHaptic()
            action()
        } label: {
            Image(systemName: glyph)
                .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 22))
                .foregroundStyle(style == .light ? Color.kuroInk : Color.kuroWhite)
                .opacity(phase == .pending ? 0.4 : 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KuroAdvanceKeyStyle(style: style))
        .disabled(!isInteractive)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(phase == .caughtUp ? KuroLocale.text("Caught up", "Auf dem neuesten Stand")
                            : phase == .pending ? KuroLocale.text("Saving", "Wird gespeichert") : "")
    }
}

private struct KuroAdvanceKeyStyle: ButtonStyle {
    let style: KuroAdvanceKey.Style

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let outer = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return configuration.label
            .background(
                outer.fill(style == .light
                           ? (pressed ? Color.kuroCanvasQuiet : Color.kuroWhite)
                           : (pressed ? Color.kuroInkPressed : Color.kuroInk))
            )
            .overlay(
                inner
                    .strokeBorder(style == .light ? Color.kuroKeyRim : Color.white.opacity(0.18), lineWidth: 1)
                    .padding(1)
            )
            .scaleEffect(pressed ? 0.98 : 1)
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
