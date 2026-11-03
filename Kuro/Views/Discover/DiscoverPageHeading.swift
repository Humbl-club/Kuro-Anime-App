import SwiftUI

// MARK: - Page section heading (Discover + Clubs redesign §4, §12.3; Home grammar G§4)
// Home's "Coming up." heading as a Discover-local view: the title in SF 24 (22 compact) semibold,
// tracking −0.85, ink, a VoiceOver header; the summary on the right in SF 10 (9 compact)
// `HomeInk.calendarSummary` #656C66, on the first baseline, 9 pt apart. When the two do not fit on
// one line (a long title, German, accessibility sizes) the summary stacks under the title. The
// Clubs lane builds `ClubPageHeading` with the same values; the integrator may fold both into one
// shared view (§12.3). Values copied from `HomeCalendarCard.swift:78-113`.

struct DiscoverPageHeading: View {
    let title: String
    var summary: String? = nil
    var compact: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            // A long title ("Manga new to you.", "Because you loved Frieren.") keeps its one line and
            // the summary steps under it, instead of the title wrapping beside the summary.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    titleText.fixedSize(horizontal: true, vertical: false)
                    if let summary, !summary.isEmpty {
                        Spacer(minLength: 0)
                        summaryText(summary, alignment: .trailing)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                stacked
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleText
            if let summary, !summary.isEmpty { summaryText(summary, alignment: .leading) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: some View {
        Text(title)
            .font(.kuroCustom(compact ? 22 : 24, weight: .semibold, relativeTo: .title2, maxSize: 40))
            .tracking(-0.85)
            .foregroundStyle(Color.kuroInk)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func summaryText(_ summary: String, alignment: TextAlignment) -> some View {
        Text(summary)
            .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 20))
            .foregroundStyle(HomeInk.calendarSummary)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The section's quiet text action ("See all 8 ›"): 13 pt medium ink in a 44 pt target.
struct DiscoverTextAction: View {
    let title: String
    let spoken: String
    let action: () -> Void

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            Text(title)
                .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 26))
                .foregroundStyle(Color.kuroInk)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(spoken)
    }
}
