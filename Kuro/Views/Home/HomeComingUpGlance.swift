import KuroCore
import SwiftUI

// MARK: - Coming up glance (prototype Poster Home, PROTOTYPE_SPEC.md §4 "Coming-up glance")
// A bordered card under the medium switch: "Coming up" (SF 14 w550, tracking −0.3, #303932) over the
// caption ("Today · 3 releases", SF 10 #687064), up to three 27 × 38 thumbnails (radius 2, 1 pt
// #fffefa rim), the count (SF 21 w450, tracking −0.6) over its label ("this week", SF 8), and ↓.
// Card: #fffefa, radius 8, 1 pt #29312918, shadow 0 1 2 #29312905, padding 10/12, gap 12 (10 and 8 at
// 320, caption 9 pt, art 34 pt high). Tapping it scrolls to the calendar (HomeView). Hidden for a new
// account. It summarises the same schedule the calendar lists, never a second source.

/// What the glance says (pure). Built from the account's release schedule, with the honest states of
/// `HomeCalendarPresentation.glanceCaption` when nothing upcoming is known.
struct HomeGlanceSummary: Equatable {
    let caption: String
    /// The big number, when there is something to count.
    let count: Int?
    /// What `count` counts: "this week", "later", "pending".
    let countLabel: String?
    /// The rows whose artwork the strip shows (≤ 3).
    let art: [ReleaseScheduleItem]
    /// The calendar has rows, so the card is a link to it.
    let linksToCalendar: Bool

    static func releases(_ count: Int, german: Bool) -> String {
        if german { return count == 1 ? "1 Veröffentlichung" : "\(count) Veröffentlichungen" }
        return count == 1 ? "1 release" : "\(count) releases"
    }

    /// `checked`: the schedule has been asked for at least once (until then "Checking dates").
    static func make(items: [ReleaseScheduleItem], copy: ReleaseCopy, offline: Bool,
                     coverage: ReleaseScheduleCoverage, checked: Bool) -> HomeGlanceSummary {
        let german = copy.german
        let groups = HomeCalendarPresentation.groups(items, copy: copy)
        let dated = groups.filter { $0.kind != .undated }
        let datedCount = dated.reduce(0) { $0 + $1.items.count }
        if let first = dated.first {
            let week = HomeCalendarPresentation.countThisWeek(items, copy: copy)
            return HomeGlanceSummary(
                caption: "\(first.label) · \(releases(first.items.count, german: german))",
                count: week > 0 ? week : datedCount,
                countLabel: week > 0 ? (german ? "diese Woche" : "this week") : (german ? "später" : "later"),
                art: Array(first.items.prefix(3)),
                linksToCalendar: true)
        }
        if let undated = groups.first(where: { $0.kind == .undated }) {
            return HomeGlanceSummary(
                caption: german ? "Termine folgen noch" : "Dates still to come",
                count: undated.items.count,
                countLabel: german ? "offen" : "pending",
                art: Array(undated.items.prefix(3)),
                linksToCalendar: true)
        }
        let caption = checked || offline
            ? HomeCalendarPresentation.glanceCaption(items: items, copy: copy, offline: offline, coverage: coverage)
            : (german ? "Termine werden geprüft" : "Checking dates")
        return HomeGlanceSummary(caption: caption, count: nil, countLabel: nil, art: [], linksToCalendar: false)
    }

    /// The spoken summary: "Coming up: Today · 3 releases, 6 this week".
    func spoken(german: Bool) -> String {
        let head = (german ? "Demnächst: " : "Coming up: ") + caption
        guard let count, let countLabel else { return head }
        return "\(head), \(count) \(countLabel)"
    }
}

/// The glance card (dumb view). `artURL` resolves a row's cover (the schedule's own, else Home's).
struct HomeComingUpGlance: View {
    let summary: HomeGlanceSummary
    let compact: Bool
    let artURL: (ReleaseScheduleItem) -> URL?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 8 : 12) {
            // The prototype's 19.6 / 14 pt lines: a little air between title and caption.
            VStack(alignment: .leading, spacing: 4) {
                Text(KuroLocale.text("Coming up", "Demnächst"))
                    .font(.kuroCustom(14, weight: .semibold, relativeTo: .subheadline, maxSize: 28))
                    .tracking(-0.3)
                    .foregroundStyle(HomeInk.glanceInk)
                Text(summary.caption)
                    .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 22))
                    .foregroundStyle(HomeInk.glanceMuted)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !summary.art.isEmpty && !dynamicTypeSize.isAccessibilitySize {
                artStrip
            }
            if let count = summary.count {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(count)")
                        .font(.kuroCustom(21, relativeTo: .title3, maxSize: 36))
                        .tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(HomeInk.glanceInk)
                        .kuroCountRoll(value: count)
                    if let label = summary.countLabel {
                        Text(label)
                            .font(.kuroCustom(8, relativeTo: .caption2, maxSize: 16))
                            .foregroundStyle(HomeInk.glanceMuted)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 39, alignment: .trailing)
            }
            if summary.linksToCalendar {
                Text("↓")
                    .font(.kuroCustom(16, relativeTo: .body, maxSize: 26))
                    .foregroundStyle(HomeInk.glanceMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, compact ? 10 : 12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(HomeInk.glanceFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HomeInk.glanceBorder, lineWidth: 1))
        .shadow(color: HomeInk.glanceShadow, radius: 1, y: 1)
        .contentShape(Rectangle())
    }

    private var artStrip: some View {
        // 69 pt strip at 390: three 27 pt thumbnails overlapping by 7.
        HStack(spacing: -7) {
            ForEach(summary.art) { item in
                HomeArtwork(url: artURL(item), maxPixelSize: 160, placeholder: HomeInk.posterFill)
                    .frame(width: 27, height: compact ? 34 : 38)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(HomeInk.glanceFill, lineWidth: 1))
                    .shadow(color: Color(hex: "26352B", opacity: Double(0x14) / 255), radius: 1, y: 1)
            }
        }
        .padding(.trailing, 2)
        .accessibilityHidden(true)
    }
}
