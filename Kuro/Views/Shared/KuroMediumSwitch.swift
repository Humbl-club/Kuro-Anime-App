import KuroCore
import SwiftUI

// MARK: - Medium switch (prototype-fidelity pass; spec §2 overrides rulebook §15.1 / D5)
// The prototype's medium words (PROTOTYPE_SPEC.md §4 "Medium switch"): heavy sans, uppercase, SF 36
// w850 tracking −1.9 (30 pt / −1.55 on phones ≤ 360 pt), via `.kuroMediumWordStyle(size:)`. The selected
// word is filled with the current title's artwork and carries a short ink rule (28 × 2); the other word
// is solid muted ink. It must never dominate the page, so callers pick `.large` only on Home and
// `.compact` (24 pt, same style) elsewhere (Collection, Lists, Browse).
// Fill: the title's `ArtworkMaterial` as a `base → deep` gradient (the same material its scene foot and
// keys use). Deliberate difference from the prototype, which clips the artwork image itself into the
// letters: the material keeps the word's contrast on the canvas guaranteed (base is ≥ 7:1 against
// white, so the dark fill reads on #fffef8) and needs no image load before the switch can paint.
// Without a material (no current title) the word takes the prototype's own fill colour (#253a2a).

struct KuroMediumSwitch: View {
    enum Size {
        /// Home: 36 pt (30 pt on phones ≤ 360 pt wide).
        case large
        /// Collection and other headers: 24 pt.
        case compact
    }

    @Binding var selection: MediaKind
    var size: Size = .large
    /// The current title's artwork material; fills the selected word. Nil: the prototype's #253a2a.
    var material: ArtworkMaterial? = nil

    init(selection: Binding<MediaKind>, size: Size = .large, material: ArtworkMaterial? = nil) {
        self._selection = selection
        self.size = size
        self.material = material
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var underline
    /// The switch's own width (0 until the first layout).
    @State private var containerWidth: CGFloat = 0

    /// The prototype's selected-word fill under its artwork (`#253a2a`).
    private static let unlitFill = Color(hex: "253A2A")
    /// The widest switch on a phone ≤ 360 pt (360 less the 16 pt small-phone gutters).
    static let smallPhoneContainer: CGFloat = 328

    /// The word size: `.compact` 24; `.large` 36, or 30 when the switch is no wider than on a 360 pt
    /// phone (the prototype's `@media(max-width:360px)`). Unmeasured (0): 36. Pure.
    static func wordSize(for size: Size, containerWidth: CGFloat) -> CGFloat {
        switch size {
        case .compact: return 24
        case .large: return containerWidth > 0 && containerWidth <= smallPhoneContainer ? 30 : 36
        }
    }

    private var wordSize: CGFloat { Self.wordSize(for: size, containerWidth: containerWidth) }

    private var selectedFill: AnyShapeStyle {
        guard let material else { return AnyShapeStyle(Self.unlitFill) }
        return AnyShapeStyle(LinearGradient(colors: [material.base.color, material.deep.color],
                                            startPoint: .top, endPoint: .bottom))
    }

    /// Side by side; at accessibility sizes the words stack so each keeps the full width and neither
    /// is cut to "Ma…" (rulebook §4).
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline,
                                     spacing: size == .large ? KuroDesignSpacing.lg : KuroDesignSpacing.md))
    }

    var body: some View {
        Group {
            if size == .large {
                // Home takes the row's width, so the small-phone size can be read from it.
                words
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            } else {
                words
            }
        }
        .kuroAnimation(KuroMotion.contextChange, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(KuroLocale.text("Medium", "Medium"))
    }

    private var words: some View {
        layout {
            word(.anime, title: "Anime")
            word(.manga, title: "Manga")
        }
    }

    private func word(_ medium: MediaKind, title: String) -> some View {
        let selected = selection == medium
        return Button {
            guard !selected else { return }
            KuroAccessibility.impactHaptic(.light)
            selection = medium
        } label: {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                Text(title)
                    .kuroMediumWordStyle(size: wordSize)
                    .lineLimit(1)
                    // The single-word switch is the one place a scale factor is allowed (rulebook §4).
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? selectedFill : AnyShapeStyle(Color.kuroMuted))
                ZStack(alignment: .leading) {
                    Color.clear.frame(height: 2)
                    if selected {
                        let rule = Rectangle()
                            .fill(Color.kuroInk)
                            .frame(width: size == .large ? 28 : 20, height: 2)
                        if reduceMotion {
                            // Reduce Motion (rulebook §8): no travel; each word's own rule crossfades.
                            rule.transition(.opacity)
                        } else {
                            rule.matchedGeometryEffect(id: "underline", in: underline)
                        }
                    }
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(selected ? "" : KuroLocale.text("Shows your \(title.lowercased()).", "Zeigt deine \(title)-Titel."))
    }
}
