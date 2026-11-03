import Foundation
import KuroWidgetSupport
import SwiftUI
import WidgetKit

// MARK: - Up next widget content (spec §10.2 "Up next", §10.3)
// Small: the soonest release — eyebrow, cover top-trailing, title, the unit split as a 10 pt word and a
// 28 pt number, then a system relative countdown ONLY when the app allowed a time
// (`countdownTarget`: an instant that is not an estimate) with the date phrase under it; otherwise the
// date phrase and, for an estimate, the dashed Estimate mark. Medium: up to 3 rows; large: up to 6.
// Every date string is the app's `ReleaseCopy` wording from the snapshot; the only time this view
// formats is `Text(target, style: .relative)`.
// Taps: rows (medium/large) are `Link`s and the small widget a `.widgetURL` to `kuro://anime|manga/<id>`
// (navigation only).

struct NextReleaseWidgetContent: View {
    let snapshot: WidgetSnapshot?
    let date: Date
    let family: WidgetFamily
    /// The language when known (the timeline entry's); nil: the snapshot's, else the device's.
    let language: Bool?

    @Environment(\.redactionReasons) private var redactionReasons

    init(snapshot: WidgetSnapshot?, date: Date, family: WidgetFamily, german: Bool? = nil) {
        self.snapshot = snapshot
        self.date = date
        self.family = family
        self.language = german
    }

    private var german: Bool { language ?? WidgetLayout.german(snapshot) }
    private var rows: [WidgetReleaseItem] { WidgetLayout.releases(snapshot, at: date, family: family) }

    var body: some View {
        content
            .foregroundStyle(WidgetPalette.ink)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            // The system relative countdown speaks the snapshot's language, like every other line.
            .environment(\.locale, WidgetLayout.locale(german: german))
    }

    @ViewBuilder private var content: some View {
        if redactionReasons.contains(.placeholder) {
            WidgetPlaceholder(rows: WidgetLayout.releaseLimit(family), coverSize: CGSize(width: 23, height: 34))
        } else {
            switch WidgetLayout.releaseState(snapshot, at: date) {
            case .signedOut:
                WidgetSignedOutMessage(german: german)
            case .empty:
                VStack(alignment: .leading, spacing: 8) {
                    WidgetEyebrow(text: WidgetCopy.upNext(german))
                    WidgetEmptyLine(text: WidgetCopy.noDates(german))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .rows:
                if family == .systemSmall, let item = rows.first {
                    NextReleaseSmall(item: item, german: german)
                        .widgetURL(item.deepLink)
                } else {
                    NextReleaseList(rows: rows, german: german, roomy: family != .systemMedium)
                }
            }
        }
    }
}

/// The small Up next widget: one release.
struct NextReleaseSmall: View {
    let item: WidgetReleaseItem
    let german: Bool

    var body: some View {
        let parts = WidgetLayout.unitParts(item.unitLabel)
        let target = WidgetLayout.countdownTarget(item)
        VStack(alignment: .leading, spacing: 0) {
            // The eyebrow keeps the full width ("NÄCHSTES KAPITEL" does not fit beside the cover);
            // the cover sits top-trailing beside the title.
            WidgetEyebrow(text: WidgetLayout.releaseEyebrow([item], german: german))
            HStack(alignment: .top, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(WidgetPalette.title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WidgetCover(name: item.thumbnail, width: 27, height: 38)
            }
            .padding(.top, 6)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if !parts.unit.isEmpty {
                    Text(parts.unit)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(WidgetPalette.muted)
                }
                if let number = parts.number {
                    Text(number)
                        .font(.system(size: 28, weight: .medium).monospacedDigit())
                        .tracking(-0.9)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            if let target {
                Text(target, style: .relative)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let phrase = item.datePhrase {
                    Text(phrase)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(WidgetPalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text(item.datePhrase ?? item.line)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                if item.isEstimate {
                    WidgetCertaintyMark(word: WidgetCopy.estimate(german))
                        .padding(.top, 3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.releaseRowLabel(title: item.title, accessibilityLine: item.accessibilityLine))
        .accessibilityAddTraits(.isLink)
    }
}

/// Medium (3) and large (6) Up next: eyebrow, then ruled rows.
struct NextReleaseList: View {
    let rows: [WidgetReleaseItem]
    let german: Bool
    /// Large: 4 pt row padding. Medium: three rows must fit the 126 pt content height, so 1 pt.
    var roomy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: roomy ? 6 : 4) {
            WidgetEyebrow(text: WidgetLayout.releaseEyebrow(rows, german: german))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { WidgetRule() }
                    WidgetLinked(url: item.deepLink) {
                        NextReleaseRow(item: item, german: german, verticalPadding: roomy ? 4 : 1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(WidgetCopy.releaseRowLabel(title: item.title,
                                                                   accessibilityLine: item.accessibilityLine))
                    .accessibilityAddTraits(.isLink)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One release row: 23 × 34 cover, title 12 medium, `line` 10 pt muted, then the trailing relative
/// time (only with `countdownTarget`) or the Estimate mark.
struct NextReleaseRow: View {
    let item: WidgetReleaseItem
    let german: Bool
    var verticalPadding: CGFloat = 4

    var body: some View {
        HStack(spacing: 10) {
            WidgetCover(name: item.thumbnail, width: 23, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.title)
                    .lineLimit(1)
                Text(item.line)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(verticalPadding > 1 ? 2 : 1)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let target = WidgetLayout.countdownTarget(item) {
                Text(target, style: .relative)
                    .font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 92, alignment: .trailing)
            } else if item.isEstimate {
                WidgetCertaintyMark(word: WidgetCopy.estimate(german))
            }
        }
        .padding(.vertical, verticalPadding)
        .frame(minHeight: 36)
        .contentShape(Rectangle())
    }
}
