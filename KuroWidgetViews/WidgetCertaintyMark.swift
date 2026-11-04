import SwiftUI

// MARK: - Certainty mark (spec §5.3, paper style)
// A hairline stamp after a release line: 8 pt uppercase, tracking .6, #4F5A52, 1 pt border, radius 3,
// padding 2/5. Solid for Confirmed / Announced, dashed #6B736C for an Estimate. The widgets show only
// the Estimate mark (a confirmed instant already shows its countdown). Decorative for VoiceOver: the
// row's label already says "expected" (`ReleaseCopy.accessibilityLine`).

struct WidgetCertaintyMark: View {
    let word: String
    var dashed: Bool = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Text(word)
            .font(.system(size: 8, weight: .regular))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(WidgetPalette.markInk)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 2)
            .padding(.horizontal, 5)
            .overlay {
                if dashed {
                    shape.strokeBorder(WidgetPalette.estimateBorder, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                } else {
                    shape.strokeBorder(WidgetPalette.markBorder, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}
