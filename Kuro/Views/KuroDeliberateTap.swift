import SwiftUI

struct KuroDeliberateTapModifier: ViewModifier {
    let action: () -> Void

    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                guard !suppressCardTaps else { return }
                action()
            }
    }
}

extension View {
    func kuroDeliberateTap(
        minDwellMs: Double = 0,
        maxMovementPt: CGFloat = 0,
        cancelMovementPt: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        modifier(KuroDeliberateTapModifier(action: action))
    }
}
