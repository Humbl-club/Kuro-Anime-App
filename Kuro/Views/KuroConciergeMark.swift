import SwiftUI

// Minimal Concierge mark (no mascot). Used for the concierge affordances across the app.
struct KuroConciergeMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.08))
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.0)
                        .blendMode(.overlay)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7)
                )

            KuroButlerGlyph()
                .fill(Color.black.opacity(0.78))
                .frame(width: size * 0.58, height: size * 0.58)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// Glyph-only version (no background circle). Useful when the parent already provides a container.
struct KuroConciergeGlyph: View {
    var size: CGFloat = 18

    var body: some View {
        KuroButlerGlyph()
            .fill(Color.black.opacity(0.78))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// A tiny "butler" silhouette (head + jacket + bow tie) that reads premium at small sizes.
private struct KuroButlerGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX

        let headR = min(w, h) * 0.17
        let head = CGRect(x: cx - headR, y: rect.minY + h * 0.14, width: headR * 2, height: headR * 2)

        let jacket = CGRect(
            x: rect.minX + w * 0.20,
            y: rect.minY + h * 0.44,
            width: w * 0.60,
            height: h * 0.44
        )

        let knot = CGRect(
            x: cx - w * 0.045,
            y: rect.minY + h * 0.52,
            width: w * 0.09,
            height: h * 0.08
        )

        var p = Path()

        // Head.
        p.addEllipse(in: head)

        // Jacket/shoulders.
        p.addRoundedRect(in: jacket, cornerSize: CGSize(width: h * 0.18, height: h * 0.18))

        // Bow tie (two wedges + knot).
        p.move(to: CGPoint(x: cx, y: rect.minY + h * 0.56))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.32, y: rect.minY + h * 0.50))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.32, y: rect.minY + h * 0.62))
        p.closeSubpath()

        p.move(to: CGPoint(x: cx, y: rect.minY + h * 0.56))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.68, y: rect.minY + h * 0.50))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.68, y: rect.minY + h * 0.62))
        p.closeSubpath()

        p.addRoundedRect(in: knot, cornerSize: CGSize(width: knot.width * 0.35, height: knot.height * 0.35))

        return p
    }
}
