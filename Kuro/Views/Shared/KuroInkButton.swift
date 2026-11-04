import SwiftUI

// MARK: - Ink buttons (spec §3.5, rulebook §7)
// Primary: a filled ink capsule, 52 pt, white sans label. At most one per screen region.
// Secondary: the invitation form, an ink label with a full ink rule and an arrow.
// Destructive: a red-outlined capsule; red is reserved for destructive actions.
// Every variant shares one pressed state (scale 0.98, 120 ms contact, cancelled by a drag) and a
// light impact on tap. Success haptics belong to the caller, after a durable accept.

/// The shared pressed state: shallow scale, immediate and reversible.
struct KuroPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .kuroAnimation(KuroMotion.contact, value: configuration.isPressed)
    }
}

struct KuroInkButton: View {
    enum Role {
        case primary
        case secondary
        case destructive
    }

    let title: String
    var role: Role = .primary
    /// Shows the branded busy mark (a short scrub line) in place of the label and ignores taps.
    var isLoading: Bool = false
    /// Light impact on tap (off for buttons that only reveal more of the same screen).
    var haptic: Bool = true
    let action: () -> Void

    init(_ title: String, role: Role = .primary, isLoading: Bool = false, haptic: Bool = true,
         action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.isLoading = isLoading
        self.haptic = haptic
        self.action = action
    }

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            guard !isLoading else { return }
            if haptic { KuroAccessibility.impactHaptic(.light) }
            action()
        } label: {
            label
        }
        .buttonStyle(KuroInkButtonStyle(role: role, isEnabled: isEnabled))
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? KuroLocale.text("In progress", "Läuft") : "")
    }

    @ViewBuilder
    private var label: some View {
        switch role {
        case .primary, .destructive:
            ZStack {
                Text(title)
                    .font(.kuroButtonLabel())
                    .multilineTextAlignment(.center)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    let ink = role == .primary ? Color.kuroWhite : Color.kuroDestructiveInk
                    KuroBusyMark(width: 40, tint: ink, track: ink.opacity(0.28))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, KuroDesignSpacing.lg)
            .contentShape(Capsule())
        case .secondary:
            VStack(spacing: KuroDesignSpacing.sm) {
                HStack(spacing: KuroDesignSpacing.md) {
                    Text(title)
                        .font(.kuroButtonLabel(weight: .medium))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isLoading {
                        KuroBusyMark(width: 24)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.kuroMeta(weight: .regular))
                            .accessibilityHidden(true)
                    }
                }
                Rectangle()
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .bottom)
            .contentShape(Rectangle())
        }
    }
}

private struct KuroInkButtonStyle: ButtonStyle {
    let role: KuroInkButton.Role
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return Group {
            switch role {
            case .primary:
                // Disabled: a quiet face with a hairline and the quiet ink label (about 5 : 1), not white
                // on a 30 % ink face (about 2 : 1, unreadable).
                configuration.label
                    .foregroundStyle(isEnabled ? Color.kuroWhite : Color.kuroInkQuiet)
                    .background(
                        Capsule().fill(isEnabled ? (pressed ? Color.kuroInkPressed : Color.kuroInk) : Color.kuroCanvasQuiet)
                    )
                    .overlay {
                        if !isEnabled { Capsule().strokeBorder(Color.kuroHairline, lineWidth: 1) }
                    }
            case .secondary:
                configuration.label
                    .foregroundStyle(isEnabled ? Color.kuroInk : Color.kuroInkQuiet)
                    .opacity(pressed ? 0.7 : 1)
            case .destructive:
                configuration.label
                    .foregroundStyle(Color.kuroDestructiveInk)
                    .background(
                        Capsule().fill(pressed ? Color.kuroDestructiveInk.opacity(0.08) : Color.clear)
                    )
                    .overlay(Capsule().strokeBorder(Color.kuroDestructiveInk.opacity(isEnabled ? 1 : 0.4), lineWidth: 1))
                    .opacity(isEnabled ? 1 : 0.5)
            }
        }
        .scaleEffect(pressed ? 0.98 : 1)
        .kuroAnimation(KuroMotion.contact, value: pressed)
    }
}
