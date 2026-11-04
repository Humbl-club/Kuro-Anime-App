import SwiftUI

// MARK: - In this issue (usability spec §5.10; Discover + Clubs redesign §6.2 item 5)
// A 1 pt `kuroHairline` rule, the eyebrow "IN THIS ISSUE · {n} SECTIONS" with "TAP TO JUMP" trailing
// (9 pt, tracking 1.05, `HomeInk.kicker`), then a two-column grid of jump links (one column at
// accessibility sizes or in the compact column): each a 44 pt row with the number ("01", 11 pt medium
// mono `kuroMuted`), the section name (13 pt medium), the count or "{n} new" (10 pt), "↓" (11 pt) and
// a 0.5 pt hairline under it. VoiceOver: "Jump to {section}, {n} titles". Every drawn section is named
// (at most six, R7). Then the Browse link row, offered only where Browse is not a pager page
// (`DiscoverBrowseEntry`), in Home's invitation link-row grammar.

struct DiscoverContentsLine: View {
    let entries: [DiscoverContents.Entry]
    let browseOffered: Bool
    let column: CGFloat
    let onJump: (String) -> Void
    let onBrowse: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if DiscoverContents.shows(entries) {
                let columns = DiscoverContents.columns(accessibility: dynamicTypeSize.isAccessibilitySize, column: column)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(DiscoverIssueCopy.contentsEyebrow(sections: entries.count, german: german))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Text(DiscoverIssueCopy.contentsTapToJump(german: german))
                            .accessibilityHidden(true)
                    }
                    .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                    .tracking(1.05)
                    .textCase(.uppercase)
                    .foregroundStyle(HomeInk.kicker)
                    .padding(.top, 10)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: columns),
                              alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            entryButton(index: index, entry: entry)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.kuroHairline).frame(height: 1).accessibilityHidden(true)
                }
            }
            if browseOffered {
                DiscoverLinkRow(kicker: DiscoverIssueCopy.browseKicker(german: german),
                                title: DiscoverIssueCopy.browseTitle(german: german),
                                action: onBrowse)
                    .padding(.top, DiscoverContents.shows(entries) ? 6 : 0)
            }
        }
    }

    private func entryButton(index: Int, entry: DiscoverContents.Entry) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            onJump(entry.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DiscoverContents.number(index))
                    .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 20))
                    .monospacedDigit()
                    .foregroundStyle(Color.kuroMuted)
                Text(entry.name)
                    .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 26))
                    .foregroundStyle(Color.kuroInk)
                    // Two lines: a long name ("Unverzichtbare Manga") is never cut at the word that
                    // tells it from its twin; the row's 44 pt minimum still holds.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(DiscoverContents.trailing(entry, german: german))
                    .font(.kuroCustom(10, weight: entry.newCount > 0 ? .medium : .regular, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(entry.newCount > 0 ? Color.kuroInk : Color.kuroMuted)
                    .lineLimit(1)
                    .fixedSize()
                Text("↓")
                    .font(.kuroCustom(11, relativeTo: .caption1, maxSize: 20))
                    .foregroundStyle(Color.kuroInk)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: DiscoverIssueLayout.contentsRow, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.kuroHairline).frame(height: 0.5).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(DiscoverIssueCopy.contentsSpoken(name: entry.name, count: entry.exact ? entry.count : nil, german: german))
        .accessibilityValue(entry.newCount > 0 ? DiscoverIssueCopy.contentsNew(entry.newCount, german: german) : "")
    }
}

/// Home's invitation link row (`HomeView.invitationAction`): an eyebrow, the 19 pt title and an arrow,
/// over a 1 pt ink rule, at least 52 pt tall. The eyebrow uses the measured 9 / 1.05 opening kicker
/// (not the 2.1-tracked `.kuroKicker()`, which this page no longer uses).
struct DiscoverLinkRow: View {
    let kicker: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker)
                    .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                    .tracking(1.05)
                    .textCase(.uppercase)
                    .foregroundStyle(HomeInk.kicker)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.kuroTitle())
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityHidden(true)
                }
                Rectangle().fill(Color.kuroInk).frame(height: 1)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(title)
    }
}
