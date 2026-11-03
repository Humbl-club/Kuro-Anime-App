import SwiftUI

// MARK: - Issue switch (Discover + Clubs redesign §6.2 item 2, D4; Home grammar G§5)
// Discover's own three-word switch in the language of Home's poster switch (`KuroPosterMediumSwitch`,
// which stays two-word and untouched): All · Anime · Manga spread edge to edge, the first word leading,
// the second centred, the third trailing, over a 1 pt `HomeInk.switchHairline`. Heavy uppercase words
// (`.kuroMediumWordStyle`) at 28 pt, 24 pt in the compact column (≤ 328); `minimumScaleFactor(0.6)` is
// only a safety net. The selected word is masked over the lead story's artwork (`KuroArtWordFill`)
// with Home's 28 × 2 `switchMark` rule under it, aligned to the word's own edge; the rule fades in
// place (`KuroMotion.settle`) and never travels. Unselected words are solid `switchUnselected`.
// At accessibility sizes the words stack. Each word is a 44 pt target with a light haptic on change.

struct DiscoverIssueSwitch: View {
    typealias Issue = EditorialDiscoverView.DiscoverMediaTypeFilter

    @Binding var selection: Issue
    /// The content column's width (the word size follows it).
    let column: CGFloat
    /// The artwork the selected word shows (the lead story's banner, else its cover).
    let artRaw: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Issue.allCases, id: \.self) { issue in
                        word(issue, alignment: .leading, stacked: true)
                    }
                }
            } else {
                ZStack {
                    word(.all, alignment: .leading, stacked: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    word(.anime, alignment: .center, stacked: false)
                        .frame(maxWidth: .infinity, alignment: .center)
                    word(.manga, alignment: .trailing, stacked: false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HomeInk.switchHairline).frame(height: 1).accessibilityHidden(true)
        }
        .kuroSwipeExclusionZone()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DiscoverIssueCopy.switchLabel(german: KuroLocale.isGerman))
    }

    private func word(_ issue: Issue, alignment: HorizontalAlignment, stacked: Bool) -> some View {
        let selected = selection == issue
        let title = issue.title(german: KuroLocale.isGerman)
        let lettering = Text(title)
            .kuroMediumWordStyle(size: DiscoverIssueLayout.switchWordSize(column: column))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        return Button {
            guard !selected else { return }
            KuroAccessibility.impactHaptic(.light)
            selection = issue
        } label: {
            VStack(alignment: alignment, spacing: 0) {
                lettering
                    .foregroundStyle(selected ? Color.clear : HomeInk.switchUnselected)
                    .overlay {
                        if selected {
                            KuroArtWordFill(raw: artRaw, fallback: .solid).mask(lettering)
                        }
                    }
                    .padding(.top, 4)
                Spacer(minLength: 4)
                Rectangle()
                    .fill(HomeInk.switchMark)
                    .frame(width: 28, height: 2)
                    .opacity(selected ? 1 : 0)
                    .animation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.settle : nil,
                               value: selected)
            }
            .frame(minHeight: stacked ? 46 : DiscoverIssueLayout.switchMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
