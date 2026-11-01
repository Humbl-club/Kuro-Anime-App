import SwiftUI

// MARK: - Home page footer (PROTOTYPE_SPEC.md §4 "Footer")
// "Your pace. Your place." on the left and the KURO mark on the right, both SF 10 in the muted ink
// (KURO w700, tracking 2), padded 20 / 22 / 28. No background, so it sits on either Home canvas.
// `HomeView` places `HomeFooter()` last in the scroll content (populated shelf and new-account block),
// with the page's own horizontal gutter already applied (the footer adds none).

struct HomeFooter: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(KuroLocale.text("Your pace. Your place.", "Dein Tempo. Dein Ort."))
                .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("KURO")
                .font(.kuroCustom(10, weight: .bold, relativeTo: .caption2, maxSize: 20))
                .tracking(2)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.kuroMuted)
        // The feed's 20 pt bottom padding plus `.app-end`'s 20 pt top, less Home's 12 pt stack spacing.
        .padding(.top, 28)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
