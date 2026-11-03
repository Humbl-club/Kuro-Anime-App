import SwiftUI

// MARK: - Club page literals (Discover + Clubs redesign, spec §4, §7)
// Home's measured values, copied (spec §4: "Lanes copy Home's constants or literals and do not invent
// new ones"). Shared by the Clubs list, the empty page and the club page; never a new shared token file.

nonisolated enum ClubRoomLayout {
    /// The page gutter: 20, or 16 when the measured container is at most 330 (HomeView `gutter`).
    static func gutter(containerWidth: CGFloat) -> CGFloat {
        containerWidth > 0 && containerWidth <= 330 ? 16 : 20
    }

    /// A small-phone column: ≤ `KuroMediumSwitch.smallPhoneContainer` (328), as Home's scenes.
    static func isCompact(columnWidth: CGFloat) -> Bool {
        columnWidth > 0 && columnWidth <= 328
    }

    /// Measured: 7 under the header (HomeView top padding).
    static let top: CGFloat = 7
    /// Measured: 12 between opening blocks (HomeView top-level stack).
    static let stack: CGFloat = 12
    /// Measured: rooms 14 apart on the list (final.html `.room + .room`).
    static let roomGap: CGFloat = 14
    /// Measured: invitation link rows 22 apart (HomeView `invitationAction` stack).
    static let linkRowGap: CGFloat = 22
    /// The cover fan: 30 × 44, overlap −9, 1.5 pt rim.
    static let fanCover = CGSize(width: 30, height: 44)
    static let fanOverlap: CGFloat = -9
    /// Hero padding: 22 / 18 / 16 (compact 18 / 12 / 12).
    static func heroPadding(compact: Bool) -> EdgeInsets {
        compact ? EdgeInsets(top: 18, leading: 12, bottom: 12, trailing: 12)
                : EdgeInsets(top: 22, leading: 18, bottom: 16, trailing: 18)
    }
    /// Tile cover (HomeAlsoWatchingTile poster): 44 × 66, radius 4.
    static let tileCover = CGSize(width: 44, height: 66)
    /// The poll option and glance thumb: 27 × 38.
    static let thumb = CGSize(width: 27, height: 38)
}

// MARK: - Page heading (lane-local copy; spec §12.3)

/// Home's page section heading ("Coming up."): 24 pt (22 compact) semibold, tracking −0.85, ink, with
/// a 10 / 9 pt `HomeInk.calendarSummary` summary on the right on the first baseline (gap 9); stacked at
/// accessibility sizes. Values identical to `DiscoverPageHeading` so the integrator can fold them.
struct ClubPageHeading: View {
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
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let summary {
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(summary)
                    .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(HomeInk.calendarSummary)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Home's in-feed sub-heading ("Also watching"): 15 pt semibold −0.2 ink + a 10 pt `kuroMuted` count.
struct ClubSubHeading: View {
    let title: String
    let count: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.kuroCustom(15, weight: .semibold, relativeTo: .subheadline, maxSize: 30))
                .tracking(-0.2)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(Color.kuroMuted)
            }
        }
        .frame(minHeight: 21)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Quiet offline band (lane-local; spec §6.4 / §7.5)

/// "**You're offline.** Showing … " in an 8 pt quiet band (white @ .5, 1 pt `HomeInk.quietBorder`,
/// 11 pt), with a trailing ink-rule "Try again →" that keeps the page's retry.
struct ClubOfflineBand: View {
    let lead: String
    let rest: String
    let retry: (() -> Void)?

    private var bandText: AttributedString {
        var head = AttributedString(lead)
        head.font = .kuroCustom(11, weight: .semibold, relativeTo: .footnote, maxSize: 24)
        head.foregroundColor = Color.kuroInk
        var tail = AttributedString(" " + rest)
        tail.foregroundColor = Color.kuroMuted
        return head + tail
    }

    var body: some View {
        let german = KuroLocale.isGerman
        HStack(alignment: .center, spacing: 12) {
            Text(bandText)
                .font(.kuroCustom(11, relativeTo: .footnote, maxSize: 24))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                ClubRuleLink(title: KuroBrandedCopy.retryTitle(german: german) + " →", action: retry)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HomeInk.quietBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// A text action with a 1 pt ink rule ("Try again →"), 44 pt target (Home's section action).
struct ClubRuleLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 22))
                    .foregroundStyle(Color.kuroInk)
                Rectangle().fill(Color.kuroInk).frame(height: 1)
            }
            .fixedSize()
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
    }
}

// MARK: - Invitation link row (Home's `invitationAction` recipe)

/// Kicker (`.kuroKicker()`), a 19 pt title (17 compact), a 13 pt → and a 1 pt ink rule; min height 52.
/// One plain button whose label reads the title (A4: `children: .combine`, activates programmatically).
struct ClubLinkRow: View {
    let kicker: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .kuroKicker()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.kuroTitle())
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.kuroCustom(13, relativeTo: .footnote, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityHidden(true)
                }
                Rectangle().fill(Color.kuroInk).frame(height: 1).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Member fills

/// Home's member stack: positional fills (`ClubRoomPalette.memberFills`), 2 pt rim, 7 pt ink, overlap −6.
struct ClubMemberFills: View {
    let initials: [String]
    var size: CGFloat = 22
    /// "+n" after the fills (members not drawn).
    var overflow: Int = 0

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(initials.enumerated()), id: \.offset) { index, letter in
                Text(letter)
                    .font(.kuroCustom(7, weight: .semibold, relativeTo: .caption2, maxSize: 12))
                    .foregroundStyle(ClubRoomPalette.memberInk)
                    .frame(width: size, height: size)
                    .background(Circle().fill(ClubRoomPalette.memberFills[index % ClubRoomPalette.memberFills.count]))
                    .overlay(Circle().strokeBorder(ClubRoomPalette.memberRim, lineWidth: 2))
            }
            if overflow > 0 {
                Text(verbatim: "+\(overflow)")
                    .font(.kuroCustom(7, weight: .semibold, relativeTo: .caption2, maxSize: 12))
                    .foregroundStyle(ClubRoomPalette.rowSecondary)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color(hex: "3A433D")))
                    .overlay(Circle().strokeBorder(ClubRoomPalette.memberRim, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
