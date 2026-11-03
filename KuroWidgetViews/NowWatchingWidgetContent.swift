import Foundation
import KuroWidgetSupport
import SwiftUI
import WidgetKit

// MARK: - Now watching widget content (spec §10.2 "Now watching", §10.3; D13)
// Small: one title — Home's kicker, 32 × 48 cover, title, the readout (unit 10 pt, count 21 mono,
// "/ total" 11 pt) and the key. Medium: 2 rows; large: 4. Each row: cover, title, the title's next
// release line when the snapshot has one ("Next · Ep. 8 · Fri 6 Nov, 21:30"), the readout and the key.
// The +1 slot is generic (`key`): the extension passes `Button(intent: AdvanceProgressIntent(item:))`
// around `WidgetKeyFace` (never a URL); KuroTests pass the bare face. A caught-up row shows the ghost ✓
// and no key. A queued row shows the new count, the face at 60 % and "Saved when Kuro opens", and no
// stamp (the app saves it through `LibraryActions.advanceQueuedProgress`).
// VoiceOver: the row is one element ("{title}, episode 6 of 23"); the key is a sibling after it.

struct NowWatchingWidgetContent<Key: View>: View {
    let snapshot: WidgetSnapshot?
    let date: Date
    let family: WidgetFamily
    /// The language when known (the timeline entry's); nil: the snapshot's, else the device's.
    let language: Bool?
    let key: (WidgetNowWatchingItem) -> Key

    @Environment(\.redactionReasons) private var redactionReasons

    init(snapshot: WidgetSnapshot?, date: Date, family: WidgetFamily, german: Bool? = nil,
         @ViewBuilder key: @escaping (WidgetNowWatchingItem) -> Key) {
        self.snapshot = snapshot
        self.date = date
        self.family = family
        self.language = german
        self.key = key
    }

    private var german: Bool { language ?? WidgetLayout.german(snapshot) }
    private var rows: [WidgetNowWatchingItem] { WidgetLayout.nowWatching(snapshot, family: family) }

    var body: some View {
        content
            .foregroundStyle(WidgetPalette.ink)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .environment(\.locale, WidgetLayout.locale(german: german))
    }

    @ViewBuilder private var content: some View {
        if redactionReasons.contains(.placeholder) {
            WidgetPlaceholder(rows: WidgetLayout.nowWatchingLimit(family), coverSize: CGSize(width: 32, height: 48))
        } else {
            switch WidgetLayout.nowWatchingState(snapshot) {
            case .signedOut:
                WidgetSignedOutMessage(german: german)
            case .empty:
                VStack(alignment: .leading, spacing: 8) {
                    WidgetEyebrow(text: WidgetCopy.nowWatching(german))
                    WidgetEmptyLine(text: WidgetCopy.nothingInProgress(german))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .rows:
                if family == .systemSmall, let item = rows.first {
                    NowWatchingSmall(item: item, german: german, keySlot: keySlot(item))
                        .widgetURL(item.deepLink)
                } else {
                    list
                }
            }
        }
    }

    private var list: some View {
        let roomy = family != .systemMedium
        return VStack(alignment: .leading, spacing: roomy ? 6 : 4) {
            WidgetEyebrow(text: WidgetLayout.nowWatchingEyebrow(rows, german: german))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { WidgetRule() }
                    HStack(spacing: 6) {
                        WidgetLinked(url: item.deepLink) {
                            NowWatchingRow(item: item, german: german,
                                           nextLine: WidgetLayout.nextReleaseLine(for: item, in: snapshot, at: date,
                                                                                  german: german))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(WidgetLayout.rowLabel(item, german: german))
                        .accessibilityAddTraits(.isLink)
                        keySlot(item)
                    }
                    .padding(.vertical, roomy ? 4 : 1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The key (advance / queued) or the ghost ✓ (caught up), labelled for VoiceOver.
    @ViewBuilder private func keySlot(_ item: WidgetNowWatchingItem) -> some View {
        switch WidgetLayout.keyPhase(item) {
        case .caughtUp:
            WidgetCaughtUpMark().accessibilityHidden(true)
        case .advance, .queued:
            key(item)
                .accessibilityLabel(WidgetCopy.markLabel(item.medium, next: WidgetLayout.nextUnit(item), german: german))
        }
    }
}

/// The readout: unit word, monospaced count and "/ total"; the queued caption under it.
struct NowWatchingReadout: View {
    let item: WidgetNowWatchingItem
    let german: Bool
    let unitSize: CGFloat
    let countSize: CGFloat
    let totalSize: CGFloat
    var alignment: HorizontalAlignment = .trailing
    /// The queued caption wraps inside this width so the title keeps its room.
    var captionWidth: CGFloat = 78

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(WidgetLayout.unitPrefix(item))
                    .font(.system(size: unitSize, weight: .regular))
                    .foregroundStyle(WidgetPalette.muted)
                Text(verbatim: "\(item.progress)")
                    .font(.system(size: countSize, weight: .medium).monospacedDigit())
                    .tracking(countSize > 16 ? -0.6 : 0)
                    .foregroundStyle(WidgetPalette.ink)
                if let total = item.total {
                    Text(verbatim: "/ \(total)")
                        .font(.system(size: totalSize, weight: .regular).monospacedDigit())
                        .foregroundStyle(WidgetPalette.muted)
                }
            }
            .lineLimit(1)
            .fixedSize()
            if item.isQueued {
                Text(WidgetCopy.savedWhenKuroOpens(german))
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                    .frame(maxWidth: captionWidth, alignment: alignment == .trailing ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The small Now watching widget: one title, the readout and the key in the bottom-trailing corner.
struct NowWatchingSmall<KeySlot: View>: View {
    let item: WidgetNowWatchingItem
    let german: Bool
    let keySlot: KeySlot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetEyebrow(text: WidgetLayout.nowWatchingEyebrow([item], german: german))
            HStack(alignment: .top, spacing: 8) {
                WidgetCover(name: item.thumbnail, width: 32, height: 48, cornerRadius: 3)
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(WidgetPalette.title)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 6)
            Spacer(minLength: 4)
            NowWatchingReadout(item: item, german: german, unitSize: 10, countSize: 21, totalSize: 11,
                               alignment: .leading, captionWidth: 120)
                .padding(.trailing, 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetLayout.rowLabel(item, german: german))
        .accessibilityAddTraits(.isLink)
        .overlay(alignment: .bottomTrailing) {
            keySlot.offset(x: 6, y: 6)
        }
    }
}

/// One Now watching row (medium / large): cover 32 × 48, title, next-release line, readout.
struct NowWatchingRow: View {
    let item: WidgetNowWatchingItem
    let german: Bool
    let nextLine: String?

    var body: some View {
        HStack(spacing: 10) {
            WidgetCover(name: item.thumbnail, width: 32, height: 48, cornerRadius: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.title)
                    .lineLimit(1)
                if let nextLine {
                    Text(nextLine)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(WidgetPalette.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NowWatchingReadout(item: item, german: german, unitSize: 9, countSize: 14, totalSize: 9)
                .layoutPriority(1)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}
