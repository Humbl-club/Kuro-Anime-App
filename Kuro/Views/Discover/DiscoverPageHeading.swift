import SwiftUI

// MARK: - Page section heading (Discover + Clubs redesign §4, §12.3; Home grammar G§4)
// Home's "Coming up." heading as a Discover-local view: the title in SF 24 (22 compact) semibold,
// tracking −0.85, ink, a VoiceOver header; the summary on the right in SF 10 (9 compact)
// `HomeInk.calendarSummary` #656C66, on the first baseline, 9 pt apart. At accessibility sizes the
// summary stacks under the title. The Clubs lane builds `ClubPageHeading` with the same values; the
// integrator may fold both into one shared view (§12.3). Values copied from
// `HomeCalendarCard.swift:78-113`.

struct DiscoverPageHeading: View {
    let title: String
    var summary: String? = nil
    var compact: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 9))
        layout {
            Text(title)
                .font(.kuroCustom(compact ? 22 : 24, weight: .semibold, relativeTo: .title2, maxSize: 40))
                .tracking(-0.85)
                .foregroundStyle(Color.kuroInk)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let summary, !summary.isEmpty {
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(summary)
                    .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(HomeInk.calendarSummary)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
