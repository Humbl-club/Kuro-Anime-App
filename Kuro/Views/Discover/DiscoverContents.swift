import SwiftUI

// MARK: - In this issue (Discover + Clubs redesign §6.2 item 5)
// A 1 pt `kuroHairline` rule, the eyebrow "IN THIS ISSUE" (9 pt, tracking 1.05, `HomeInk.kicker`), then
// the sections drawn below as a wrapping line: each a 12 pt medium name with its real count in 10 pt
// `kuroMuted`, at most five, then "+n more". A name scrolls to its section; "+n more" opens the fold
// (when there is one) and scrolls there. Each entry is a 22 pt line whose hit area reaches 44 pt: 3 pt
// above the text and 19 below, so a target never reaches up over the line above (the next line, drawn
// later, wins its own text), and the lines stay as tight as drawn. Then the Browse link row, offered
// only where Browse is not a pager page (`DiscoverBrowseEntry`), in Home's invitation link-row grammar.

struct DiscoverContentsLine: View {
    let line: DiscoverContents.Line?
    let browseOffered: Bool
    let onJump: (String) -> Void
    let onMore: (String) -> Void
    let onBrowse: () -> Void

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let line {
                VStack(alignment: .leading, spacing: 6) {
                    Text(DiscoverIssueCopy.contentsEyebrow(german: german))
                        .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                        .tracking(1.05)
                        .textCase(.uppercase)
                        .foregroundStyle(HomeInk.kicker)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 10)
                    DiscoverContentsFlow(horizontalSpacing: 14, lineSpacing: 6 - 22) {
                        ForEach(line.names) { entry in
                            entryButton(name: entry.name, count: "\(entry.count)",
                                        spoken: DiscoverIssueCopy.contentsSpoken(name: entry.name, count: entry.count, german: german)) {
                                onJump(entry.id)
                            }
                        }
                        if let more = line.more, let target = line.moreTarget {
                            let title = DiscoverIssueCopy.contentsMore(more, german: german)
                            entryButton(name: title, count: "↓", spoken: title) { onMore(target) }
                        }
                    }
                    // The first and last rows' extra hit area sits inside the block.
                    .padding(.top, -3)
                    .padding(.bottom, -19)
                }
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.kuroHairline).frame(height: 1).accessibilityHidden(true)
                }
            }
            if browseOffered {
                DiscoverLinkRow(kicker: DiscoverIssueCopy.browseKicker(german: german),
                                title: DiscoverIssueCopy.browseTitle(german: german),
                                action: onBrowse)
                    .padding(.top, line == nil ? 0 : 6)
            }
        }
    }

    private func entryButton(name: String, count: String, spoken: String, action: @escaping () -> Void) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(name)
                    .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(Color.kuroInk)
                Text(count)
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(Color.kuroMuted)
            }
            .lineLimit(1)
            .frame(minHeight: 22)
            // The 22 pt line becomes a 44 pt target that reaches down, never up into the line above.
            .padding(.top, 3)
            .padding(.bottom, 19)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(spoken)
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

/// A wrapping line with separate gaps between items and between lines (a negative line gap lets 44 pt
/// targets overlap so 22 pt lines sit 6 pt apart). Lane-local; `FlowLayout` keeps one spacing.
struct DiscoverContentsFlow: Layout {
    let horizontalSpacing: CGFloat
    let lineSpacing: CGFloat

    private func arrange(width: CGFloat, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        var positions: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            widest = max(widest, x + size.width)
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        return (positions, CGSize(width: min(width, widest), height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = arrange(width: width, subviews: subviews)
        return CGSize(width: proposal.width ?? result.size.width, height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }
}
