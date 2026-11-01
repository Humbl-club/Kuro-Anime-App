import KuroCore
import SwiftUI

// MARK: - Medium switch (spec §3.5, D5, rulebook §4/§7)
// The two medium words in the native heavy serif, mixed case (D5 keeps it; do not change the
// typeface without an owner call). The selected word is ink with a short ink rule under it; the other
// word is quiet ink. It must never dominate the page (composition review), so callers pick `.large`
// only on Home and `.compact` elsewhere (Collection, Lists).

struct KuroMediumSwitch: View {
    enum Size {
        /// Home: 40 pt (32 pt at accessibility sizes).
        case large
        /// Collection and other headers: 24 pt.
        case compact
    }

    @Binding var selection: MediaKind
    var size: Size = .large

    init(selection: Binding<MediaKind>, size: Size = .large) {
        self._selection = selection
        self.size = size
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var underline

    private var font: Font {
        switch size {
        case .large:
            let base: CGFloat = dynamicTypeSize.isAccessibilitySize ? 32 : 40
            return .kuroCustom(base, weight: .heavy, design: .serif, relativeTo: .largeTitle, maxSize: 48)
        case .compact:
            return .kuroCustom(24, weight: .heavy, design: .serif, relativeTo: .title2, maxSize: 36)
        }
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
        layout {
            word(.anime, title: "Anime")
            word(.manga, title: "Manga")
        }
        .kuroAnimation(KuroMotion.contextChange, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(KuroLocale.text("Medium", "Medium"))
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
                    .font(font)
                    .lineLimit(1)
                    // The single-word switch is the one place a scale factor is allowed (rulebook §4).
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? Color.kuroInk : Color.kuroInkQuiet)
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
