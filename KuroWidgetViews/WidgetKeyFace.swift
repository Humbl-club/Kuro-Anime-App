import KuroWidgetSupport
import SwiftUI

// MARK: - The +1 key face (spec §10.2 "The key")
// The raised `.ink` face of `KuroAdvanceKey` (34 pt, radius 7, `kuroKeyDarkTop → kuroKeyDarkBottom`,
// 1 pt #20282326 border, inset white highlight, 0 1 2 drop), with a white "+1" in 12 semibold, inside
// a 44 pt target. It is not material: the snapshot carries no artwork material. A queued +1 dims the
// face to 60 %. There is no confirm stamp or animation in a widget (spec D13).
// The face is only the label: the extension wraps it in `Button(intent: AdvanceProgressIntent(item:))`
// (never a URL); tests and the app host render it bare.

struct WidgetKeyFace: View {
    let queued: Bool

    init(queued: Bool = false) {
        self.queued = queued
    }

    init(item: WidgetNowWatchingItem) {
        self.queued = WidgetLayout.keyPhase(item) == .queued
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        ZStack {
            shape
                .fill(LinearGradient(colors: [WidgetPalette.keyTop, WidgetPalette.keyBottom],
                                     startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: WidgetPalette.keyHighlight, radius: 0, x: 0, y: 1)))
                .overlay(shape.strokeBorder(WidgetPalette.keyBorder, lineWidth: 1))
                .shadow(color: WidgetPalette.keyDrop, radius: 1, x: 0, y: 1)
                .frame(width: 34, height: 34)
            Text("+1")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WidgetPalette.keyInk)
        }
        .opacity(queued ? 0.6 : 1)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

/// The caught-up slot: the ghost ✓ (12 pt light #767B77) in the same 44 pt footprint, no button.
struct WidgetCaughtUpMark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .light))
            .foregroundStyle(WidgetPalette.caughtUp)
            .frame(width: 44, height: 44)
    }
}
