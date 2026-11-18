// W9: the Collection page's two organisation entries: the tag words (a local filter over the whole library)
// and the "Your lists" link (opens the lists journey). Both are text, monochrome, 44 pt targets.

import SwiftUI

/// Tag words under the medium switch. Choosing one filters Collection to that tag across the whole library;
/// choosing it again clears the filter.
struct FolioTagWords: View {
    let tags: [String]
    let selected: String?
    let gutter: CGFloat
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KuroDesignSpacing.md) {
                ForEach(tags, id: \.self) { tag in
                    let isSelected = selected.map { LibraryTagRules.key($0) == LibraryTagRules.key(tag) } ?? false
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        onSelect(isSelected ? nil : tag)
                    } label: {
                        Text(tag)
                            .font(.kuroMeta(weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.kuroInk : Color.kuroInkSecondary)
                            .underline(isSelected, color: Color.kuroInk)
                            .lineLimit(1)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("folio.tag.\(tag)")
                }
            }
            .padding(.horizontal, gutter)
        }
        .accessibilityElement(children: .contain)
    }
}

/// "Your lists · 3 ›" in the Collection header.
struct FolioListsLink: View {
    let count: Int
    let gutter: CGFloat
    var forcedGerman: Bool?
    let action: () -> Void

    private var german: Bool { forcedGerman ?? KuroLocale.isGerman }

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            HStack(spacing: KuroDesignSpacing.xs) {
                Text("\(OrganiseCopy.string(.yourLists, german: german)) · \(count)")
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                Image(systemName: "chevron.right")
                    .font(.kuroCustom(11, weight: .semibold, relativeTo: .caption1, maxSize: 16))
                    .foregroundStyle(Color.kuroInkQuiet)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, gutter)
        .accessibilityIdentifier("folio.yourLists")
    }
}
