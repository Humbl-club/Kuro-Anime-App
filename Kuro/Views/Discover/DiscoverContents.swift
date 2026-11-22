import SwiftUI

// MARK: - In this issue (usability spec §5.10; Discover + Clubs redesign §6.2 item 5)
// A 1 pt `kuroHairline` rule, the eyebrow "IN THIS ISSUE · {n} SECTIONS" with "TAP TO JUMP" trailing
// (9 pt, tracking 1.05, `HomeInk.kicker`), then a two-column grid of jump links (one column at
// accessibility sizes or in the compact column): each a 44 pt row with the number ("01", 11 pt medium
// mono `kuroMuted`), the section name (13 pt medium), the count or "{n} new" (10 pt), "↓" (11 pt) and
// a 0.5 pt hairline under it. VoiceOver: "Jump to {section}, {n} titles". Every drawn section is named
// (at most six, R7). Then the Browse link row, offered only where Browse is not a pager page
// (`DiscoverBrowseEntry`), in Home's invitation link-row grammar.

/// A calm warm-paper quick-find bar directly beneath the issue switch: 1-tap Search plus 1-tap
/// Filters (`BrowseView` genres, year, season, format, status), stacking cleanly at AX sizes.
struct DiscoverQuickFindBar: View {
    let canSearch: Bool
    let canFilter: Bool
    var canSchedule: Bool = false
    let onSearch: () -> Void
    let onFilter: () -> Void
    var onSchedule: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                if canSearch { searchButton }
                HStack(spacing: 8) {
                    if canSchedule { scheduleButton(fullWidth: !canFilter) }
                    if canFilter { filterButton(fullWidth: !canSchedule) }
                }
            }
        } else {
            HStack(spacing: 8) {
                if canSearch { searchButton }
                if canSchedule { scheduleButton(fullWidth: false) }
                if canFilter { filterButton(fullWidth: !canSearch && !canSchedule) }
            }
        }
    }

    private func scheduleButton(fullWidth: Bool) -> some View {
        Button {
            guard TastePlanKey.acceptsTap(suppressCardTaps: suppressCardTaps) else { return }
            KuroAccessibility.impactHaptic(.light)
            onSchedule?()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.kuroCustom(13, weight: .semibold, relativeTo: .footnote, maxSize: 22))
                    .foregroundStyle(Color.kuroControlInk)
                    .accessibilityHidden(true)
                Text(german ? "Plan" : "Schedule")
                    .font(.kuroCustom(13, weight: .semibold, relativeTo: .footnote, maxSize: 22))
                    .foregroundStyle(Color.kuroControlInk)
                    .lineLimit(1)
                if fullWidth {
                    Spacer(minLength: 4)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
            .background(Color.kuroControlFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.kuroKeyRim, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(german ? "7-Tage-Release-Kalender" : "7-day release schedule")
    }

    private var searchButton: some View {
        Button {
            guard TastePlanKey.acceptsTap(suppressCardTaps: suppressCardTaps) else { return }
            KuroAccessibility.impactHaptic(.light)
            onSearch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.kuroCustom(14, weight: .semibold, relativeTo: .footnote, maxSize: 22))
                    .foregroundStyle(Color.kuroInkSecondary)
                    .accessibilityHidden(true)
                Text(DiscoverIssueCopy.quickSearchPlaceholder(german: german))
                    .font(.kuroCustom(15, weight: .regular, relativeTo: .body, maxSize: 26))
                    .foregroundStyle(Color.kuroInkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                    Text("⌘K")
                        .font(.kuroCustom(11, weight: .medium, relativeTo: .caption2, maxSize: 16))
                        .foregroundStyle(Color.kuroMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.kuroKeyRim, lineWidth: 0.8))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(Color.kuroControlFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(DiscoverIssueCopy.quickSearchPlaceholder(german: german))
    }

    private func filterButton(fullWidth: Bool) -> some View {
        Button {
            guard TastePlanKey.acceptsTap(suppressCardTaps: suppressCardTaps) else { return }
            KuroAccessibility.impactHaptic(.light)
            onFilter()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.kuroCustom(13, weight: .semibold, relativeTo: .footnote, maxSize: 22))
                    .foregroundStyle(Color.kuroControlInk)
                    .accessibilityHidden(true)
                Text(DiscoverIssueCopy.quickFilterLabel(german: german))
                    .font(.kuroCustom(14, weight: .semibold, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(Color.kuroControlInk)
                    .lineLimit(1)
                if fullWidth {
                    Spacer(minLength: 4)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
            .background(Color.kuroControlFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.kuroKeyRim, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(DiscoverIssueCopy.quickFilterSpoken(german: german))
    }
}

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
                    if dynamicTypeSize.isAccessibilitySize {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: columns),
                                  alignment: .leading, spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                entryButton(index: index, entry: entry)
                            }
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    jumpChip(index: index, entry: entry)
                                }
                            }
                        }
                        .scrollClipDisabled()
                        .kuroSwipeExclusionZone()
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.kuroHairline).frame(height: 0.5).accessibilityHidden(true)
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

    private func jumpChip(index: Int, entry: DiscoverContents.Entry) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            onJump(entry.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(DiscoverContents.number(index))
                    .font(.kuroCustom(10, weight: .medium, relativeTo: .caption2, maxSize: 18))
                    .monospacedDigit()
                    .foregroundStyle(Color.kuroMuted)
                Text(entry.name)
                    .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 22))
                    .foregroundStyle(Color.kuroInk)
                    .lineLimit(1)
                    .fixedSize()
                if entry.newCount > 0 {
                    Circle()
                        .fill(Color.kuroInk.opacity(0.75))
                        .frame(width: 4, height: 4)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 2 }
                        .accessibilityHidden(true)
                }
                Text("↓")
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 18))
                    .foregroundStyle(Color.kuroMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DiscoverIssueLayout.contentsRow, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(DiscoverIssueCopy.contentsSpoken(name: entry.name, count: entry.exact ? entry.count : nil, german: german))
        .accessibilityValue(entry.newCount > 0 ? DiscoverIssueCopy.contentsNew(entry.newCount, german: german) : "")
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
                    .monospacedDigit()
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
