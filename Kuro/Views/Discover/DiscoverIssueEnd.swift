import SwiftUI

// MARK: - The end of the issue (usability spec §5.7, R7)
// A 1 pt `kuroHairline`, the 24 pt seal (Home's footer wordmark at 30 % ink, fading in once per issue),
// "You're caught up for today." (24 / −0.85), the tally (12 pt `kuroMuted`: "{s} sections, {t} titles.",
// what the reader did this visit, "A new issue tomorrow morning."), then Home's invitation link rows
// (Browse where it is offered, Search), then "MORE LISTS" and a wrapping row of list names (13 pt
// medium + ›), each opening its See all journey. Nothing on the page becomes unreachable (D7).

struct DiscoverIssueEnd: View {
    struct MoreLink: Identifiable {
        let id: String
        let name: String
        let action: () -> Void
    }

    let sections: Int
    let titles: Int
    let planned: Int
    let hidden: Int
    let seen: Int
    /// What "marked as seen" says on this issue (read on Manga, either on All).
    var seenWord: DiscoverIssueCopy.SeenWord = .seen
    let browseOffered: Bool
    let moreLists: [MoreLink]
    let onBrowse: () -> Void
    let onSearch: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sealShown = false

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.kuroHairline).frame(height: 1).accessibilityHidden(true)
            Text(verbatim: "KURO")
                .font(.kuroCustom(24, weight: .bold, relativeTo: .title2, maxSize: 36))
                .tracking(2)
                .foregroundStyle(Color.kuroInk.opacity(0.3))
                .opacity(sealShown ? 1 : 0)
                .padding(.top, 24)
                .accessibilityHidden(true)
                .onAppear {
                    guard !sealShown else { return }
                    if KuroMotion.playsMotionNow(reduceMotion: reduceMotion) {
                        withAnimation(KuroMotion.medium) { sealShown = true }
                    } else {
                        sealShown = true
                    }
                }
            Text(DiscoverIssueCopy.endTitle(german: german))
                .font(.kuroCustom(24, weight: .semibold, relativeTo: .title2, maxSize: 40))
                .tracking(-0.85)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(DiscoverIssueCopy.endTally(sections: sections, titles: titles, german: german))
                if let done = DiscoverIssueCopy.endActions(planned: planned, hidden: hidden, seen: seen, seenWord: seenWord, german: german) {
                    Text(done)
                }
                Text(DiscoverIssueCopy.endTomorrow(german: german))
            }
            .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
            .foregroundStyle(Color.kuroMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 6) {
                if browseOffered {
                    DiscoverLinkRow(kicker: DiscoverIssueCopy.browseKicker(german: german),
                                    title: DiscoverIssueCopy.browseTitle(german: german), action: onBrowse)
                }
                DiscoverLinkRow(kicker: DiscoverIssueCopy.searchKicker(german: german),
                                title: DiscoverIssueCopy.searchTitle(german: german), action: onSearch)
            }
            .padding(.top, 18)

            if !moreLists.isEmpty {
                Text(DiscoverIssueCopy.moreListsEyebrow(german: german))
                    .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                    .tracking(1.05)
                    .textCase(.uppercase)
                    .foregroundStyle(HomeInk.kicker)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 22)
                FlowLayout(spacing: 14) {
                    ForEach(moreLists) { link in
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            link.action()
                        } label: {
                            Text(link.name + " ›")
                                .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 26))
                                .foregroundStyle(Color.kuroInk)
                                .lineLimit(1)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(HomeContactStyle())
                        .accessibilityLabel(link.name)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
