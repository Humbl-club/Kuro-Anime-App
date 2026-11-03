import SwiftUI

// MARK: - Refine and sort words (details-songs spec D21, §9)
// The grammar of Discover's `DiscoverRefineRow` (11 pt medium, ink when selected and `kuroMuted`
// otherwise, a 16 × 1.5 ink rule under the selected word, 16 pt apart, each a 44 pt target,
// `HomeContactStyle`), written generic because `DiscoverRefineRow` is typed to `DiscoverRailFilter`.
// Replaces the black `EntityFilterBar` pills and the capsule sort control on the entity pages.

struct EntityWords<Option: Hashable & EntityOptionTitled>: View {
    let options: [Option]
    @Binding var selection: Option
    /// VoiceOver hears the group by this name ("Filter works", "Sort").
    let groupLabel: String

    var body: some View {
        HStack(spacing: 16) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    guard !selected else { return }
                    KuroAccessibility.impactHaptic(.light)
                    selection = option
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.title)
                            .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 22))
                            .foregroundStyle(selected ? Color.kuroInk : Color.kuroMuted)
                            .lineLimit(1)
                            .fixedSize()
                        Rectangle()
                            .fill(selected ? Color.kuroInk : Color.clear)
                            .frame(width: 16, height: 1.5)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(groupLabel)
    }
}

/// One row under a section heading: refine words on the left (only when there is a choice), the sort words
/// on the right. Too narrow for one line (320 pt, large type): the sort words move under the refine words.
struct EntityRefineSortRow<Filter: Hashable & EntityOptionTitled>: View {
    let filters: [Filter]
    @Binding var filter: Filter
    @Binding var sort: EntitySortMode

    var body: some View {
        let german = KuroLocale.isGerman
        let refine = filters.count > 1
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                if refine {
                    EntityWords(options: filters, selection: $filter, groupLabel: EntityPageCopy.refineLabel(german: german))
                }
                Spacer(minLength: 8)
                EntityWords(options: EntitySortMode.allCases, selection: $sort, groupLabel: EntityPageCopy.sortLabel(german: german))
            }
            VStack(alignment: .leading, spacing: 0) {
                if refine {
                    ScrollView(.horizontal, showsIndicators: false) {
                        EntityWords(options: filters, selection: $filter, groupLabel: EntityPageCopy.refineLabel(german: german))
                    }
                    .scrollClipDisabled()
                    .kuroSwipeExclusionZone()
                }
                EntityWords(options: EntitySortMode.allCases, selection: $sort, groupLabel: EntityPageCopy.sortLabel(german: german))
            }
        }
    }
}

/// The sort words alone (studio and author pages, where there is nothing to refine by medium).
struct EntitySortRow: View {
    @Binding var sort: EntitySortMode

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            EntityWords(options: EntitySortMode.allCases, selection: $sort,
                        groupLabel: EntityPageCopy.sortLabel(german: KuroLocale.isGerman))
        }
    }
}
