import KuroCore
import KuroLibrary
import SwiftUI
import UIKit

// MARK: - Detail hero parts (details-songs spec §6.2, §7.2, §7.3, §5.3)
// The anime hero becomes Home's scene card: under the title its foot gains two fact rows (the facts
// line, then the next-release row with the bell), and Home's season tab sits on the art's bottom
// edge. The manga page gains a facts line under its serif title and a next-chapter glance (Home's
// glance card) above the story. Words come from `DetailPassRules.swift` and `ReleaseCopy`; a time
// appears only for `item.showsTime`; an estimate carries the dashed mark and never a bell.

// MARK: Certainty mark (§5.3)

struct DetailCertaintyMark: View {
    enum Tone { case paper, onMaterial }
    let basis: ReleaseBasis
    var tone: Tone = .paper

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let estimate = basis == .estimated
        let ink = tone == .paper ? Color(hex: "4F5A52") : Color(hex: "DCE2DF")
        let border: Color = estimate ? Color(hex: "6B736C") : (tone == .paper ? Color(hex: "4F5A52").opacity(0.35) : Color.white.opacity(0.35))
        Text(DetailNextRelease.markWord(basis, german: KuroLocale.isGerman).uppercased())
            .font(.detailSF(8, .medium, relativeTo: .caption2))
            .tracking(0.6)
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.vertical, 2)
            .padding(.horizontal, 5)
            .overlay(shape.strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: estimate ? [2, 2] : [])))
            // The row reads the basis word as its value (§6.2).
            .accessibilityHidden(true)
    }
}

// MARK: Facts line (§6.2 item 2)

struct DetailFactsLine: View {
    let parts: [DetailFacts.Part]
    var tone: DetailCertaintyMark.Tone = .onMaterial
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The line's measured width: 9 pt in a compact column (a 320 pt phone), 10 pt otherwise (§6.10).
    @State private var width: CGFloat = 0

    /// A 320 pt phone's hero column (320 − 2 × 24); the page column there is ≤ 328.
    nonisolated static func size(width: CGFloat) -> CGFloat { width > 0 && width <= 280 ? 9 : 10 }

    var body: some View {
        if !parts.isEmpty {
            let base = tone == .onMaterial ? HomeInk.footFact : DetailInk.author
            let accent = tone == .onMaterial ? Color.white.opacity(0.95) : Color.kuroInk
            parts.enumerated().reduce(Text(verbatim: "")) { line, item in
                let (index, part) = item
                let separator = index == 0 ? Text(verbatim: "") : Text(verbatim: " · ").foregroundStyle(base)
                let piece = part.isScore
                    ? Text(part.text).fontWeight(.medium).foregroundStyle(accent)
                    : Text(part.text).foregroundStyle(base)
                return line + separator + piece
            }
            .font(.detailSF(Self.size(width: width), relativeTo: .caption1))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { value in
                if abs(width - value) > 0.5 { width = value }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DetailFacts.spoken(parts))
        }
    }
}

// MARK: Next-release row (§6.2 item 3)

/// The scene foot's fact row: kicker, the `ReleaseCopy` line and its certainty mark on the left; the
/// day count and the bell on the right (under the line at accessibility sizes).
struct DetailNextReleaseRow: View {
    let item: ReleaseScheduleItem
    let showsBell: Bool
    /// Renders: the bell's state without the store.
    var previewBellOn: Bool? = nil
    let onBell: (DetailReminderRule.Change) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let copy = ReleaseCopy.current()
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        layout {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(DetailNextRelease.kicker(item.unitKind, german: copy.german))
                        .font(.detailSF(7, .semibold, relativeTo: .caption2))
                        .tracking(1.4)
                        .foregroundStyle(DetailInk.kicker)
                    Text(copy.line(item, undatedFallback: true))
                        .font(.detailSF(12, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Color(hex: "FAFAFA"))
                        .lineLimit(stacked ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if DetailNextRelease.showsMark(item) {
                        DetailCertaintyMark(basis: item.basis, tone: .onMaterial).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !stacked, let days = DetailNextRelease.dayCount(copy.daysFromToday(item), german: copy.german) {
                    Text(days)
                        .font(.detailSF(10, relativeTo: .caption1))
                        .foregroundStyle(HomeInk.footFact)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.accessibilityLine(item))
            .accessibilityValue(DetailNextRelease.spokenValue(item, copy: copy))
            if stacked, let days = DetailNextRelease.dayCount(copy.daysFromToday(item), german: copy.german) {
                Text(days)
                    .font(.detailSF(10, relativeTo: .caption1))
                    .foregroundStyle(HomeInk.footFact)
                    .accessibilityHidden(true)
            }
            if showsBell {
                DetailReminderBell(item: item, tone: .onMaterial, previewOn: previewBellOn, onChange: onBell)
                    .overlay(alignment: .leading) {
                        if !stacked {
                            Rectangle().fill(Color.white.opacity(Double(0x24) / 255)).frame(width: 1, height: 48)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .padding(.top, 9)
        .frame(minHeight: 44, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(Double(0x0D) / 255)).frame(height: 1).accessibilityHidden(true)
        }
    }
}

// MARK: Bell (§6.2, §11.4)

/// The title's reminder bell. State and the tap go through `ReleasesStore` (the platform lane's
/// notification owner): turning it on is an explicit user action, the only place besides the Profile
/// toggle that may show the permission prompt.
struct DetailReminderBell: View {
    let item: ReleaseScheduleItem
    var tone: DetailCertaintyMark.Tone = .onMaterial
    var previewOn: Bool? = nil
    let onChange: (DetailReminderRule.Change) -> Void
    @Environment(ReleasesStore.self) private var releases
    @State private var working = false

    private var isOn: Bool { previewOn ?? releases.releaseNotificationsOn(for: item.key) }

    var body: some View {
        let ink = tone == .onMaterial ? Color.white.opacity(0.9) : Color.kuroInk
        Button {
            guard !working, previewOn == nil else { return }
            working = true
            let turnOn = !isOn
            Task { @MainActor in
                let result = await releases.setReleaseNotification(turnOn, for: item.key)
                working = false
                let change: DetailReminderRule.Change
                switch result {
                case .enabled: change = .on
                case .disabled: change = .off
                case .permissionDenied: change = .denied
                case .signedOut: change = .failed
                }
                if change == .on { KuroAccessibility.impactHaptic(.light) }
                onChange(change)
            }
        } label: {
            Image(systemName: isOn ? "bell.fill" : "bell")
                .font(.kuroCustom(15, weight: .regular, relativeTo: .body, maxSize: 22))
                .foregroundStyle(ink)
                .opacity(working ? 0.5 : 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(DetailReminderRule.label(item, isOn: isOn, german: KuroLocale.isGerman))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .task(id: item.key) {
            guard previewOn == nil else { return }
            await releases.refreshReleaseNotificationState()
        }
    }
}

// MARK: Season tab (§6.2)

/// Home's season tab on the art's bottom-left edge (a detail-local copy: Home's is private). A tap
/// scrolls to the Seasons section; there is no new picker.
struct DetailSeasonTab: View {
    let number: Int
    let total: Int
    let onTap: () -> Void

    var body: some View {
        let german = KuroLocale.isGerman
        Button(action: onTap) {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(DetailSeasonTabRule.word(german: german))
                    .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 14))
                    .tracking(0.3)
                Text("\(number)")
                    .font(.kuroCustom(17, weight: .semibold, relativeTo: .headline, maxSize: 28))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(DetailSeasonTabRule.of(total, german: german))
                    .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 16))
                    .foregroundStyle(Color(hex: "6B776D"))
            }
            .foregroundStyle(HomeInk.tabInk)
            .padding(.horizontal, 8)
            .frame(minHeight: 31)
            .fixedSize(horizontal: false, vertical: true)
            .background(HomeInk.tabFace, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
            .shadow(color: Color.white.opacity(Double(0x65) / 255), radius: 0, y: -1)
            .frame(minWidth: 44, minHeight: 44, alignment: .bottomLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .accessibilityLabel(DetailSeasonTabRule.spoken(number, of: total, german: german))
    }
}

// MARK: Manga next-chapter glance (§7.3)

/// Home's glance card with the manga calendar's date chip: the next chapter or volume, its certainty,
/// its source and (rarely, for a publisher instant) the bell.
struct DetailMangaNextGlance: View {
    let item: ReleaseScheduleItem
    let showsBell: Bool
    var previewBellOn: Bool? = nil
    let onBell: (DetailReminderRule.Change) -> Void

    var body: some View {
        let copy = ReleaseCopy.current()
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                dateChip(copy)
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.line(item, undatedFallback: true))
                        .font(.detailSF(14, .semibold, relativeTo: .subheadline))
                        .tracking(-0.3)
                        .foregroundStyle(HomeInk.glanceInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if DetailNextRelease.showsMark(item) {
                        DetailCertaintyMark(basis: item.basis, tone: .paper)
                    }
                    let captions = [copy.sourceAttribution(item),
                                    item.basis == .estimated ? DetailNextRelease.estimateNote(german: copy.german) : nil]
                        .compactMap { $0 }
                    if !captions.isEmpty {
                        Text(captions.joined(separator: " · "))
                            .font(.detailSF(10, relativeTo: .caption1))
                            .foregroundStyle(HomeInk.glanceMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.accessibilityLine(item))
            .accessibilityValue([DetailNextRelease.spokenValue(item, copy: copy),
                                 item.basis == .estimated ? DetailNextRelease.estimateNote(german: copy.german) : nil]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". "))
            if showsBell {
                DetailReminderBell(item: item, tone: .paper, previewOn: previewBellOn, onChange: onBell)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(minHeight: 72)
        .background(HomeInk.glanceFill, in: shape)
        .overlay(shape.strokeBorder(HomeInk.glanceBorder, lineWidth: 1))
        .shadow(color: HomeInk.glanceShadow, radius: 1, y: 1)
    }

    @ViewBuilder
    private func dateChip(_ copy: ReleaseCopy) -> some View {
        if let day = copy.calendarDay(item), let heading = copy.dayHeading(day) {
            VStack(spacing: 0) {
                Text(heading.day)
                    .font(.kuroCustom(19, weight: .medium, relativeTo: .title3, maxSize: 30))
                    .monospacedDigit()
                    .foregroundStyle(HomeInk.glanceInk)
                Text(heading.month)
                    .font(.detailSF(9, relativeTo: .caption2))
                    .foregroundStyle(Color(hex: "667267"))
            }
            .frame(width: 40, height: 44)
            .background(Color(hex: "ECEEE4"),
                        in: UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 4,
                                                   topTrailingRadius: 10, style: .continuous))
            .accessibilityHidden(true)
        } else {
            DetailBrandedTile(kind: copy.german ? "Kap." : "Ch.")
                .frame(width: 40, height: 44)
        }
    }
}

// MARK: Bell toast

enum DetailReminderToast {
    /// The page toast for a bell result (§11.4); `.denied` offers Settings.
    @MainActor
    static func state(_ change: DetailReminderRule.Change, openURL: OpenURLAction) -> KuroToastState {
        let german = KuroLocale.isGerman
        switch change {
        case .on, .off:
            return KuroToastState(kind: .success, title: DetailReminderRule.toast(change, german: german),
                                  subtitle: nil, actionTitle: nil, onAction: nil)
        case .denied:
            return KuroToastState(kind: .info, title: DetailReminderRule.toast(change, german: german), subtitle: nil,
                                  actionTitle: DetailReminderRule.settings(german: german),
                                  onAction: {
                                      if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                                  })
        case .failed:
            return KuroToastState(kind: .error, title: DetailReminderRule.toast(change, german: german),
                                  subtitle: nil, actionTitle: nil, onAction: nil)
        }
    }
}
