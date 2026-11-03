import AppIntents
import KuroWidgetSupport
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Widget views (PLATFORM lane placeholder)
// Functional, deliberately plain layouts so the extension builds, renders and exercises the data
// contract. The widget UI lane replaces these bodies in Home's grammar (HOME_GRAMMAR.md); the data
// contract (`KuroWidgetEntry`, `AdvanceProgressIntent(item:)`, `WidgetChrome`) stays.

/// The prototype palette, copied (the extension does not link the app's design system).
enum WidgetPalette {
    static let ink = Color(red: 0x25 / 255, green: 0x26 / 255, blue: 0x25 / 255)
    static let canvas = Color(red: 0xff / 255, green: 0xfe / 255, blue: 0xf8 / 255)
    static let muted = Color(red: 0x69 / 255, green: 0x6c / 255, blue: 0x6b / 255)
}

/// EN/DE chrome strings of the widgets (the app's `KuroLocale` is not linked here; the snapshot says
/// which language the app rendered).
enum WidgetChrome {
    static func upNext(_ german: Bool) -> String { german ? "Als Nächstes" : "Up next" }
    static func nowWatching(_ german: Bool) -> String { german ? "Gerade dabei" : "Now watching" }
    static func signedOut(_ german: Bool) -> String {
        german ? "Öffne Kuro, um deine Titel hier zu sehen." : "Open Kuro to see your titles here."
    }
    static func nothingScheduled(_ german: Bool) -> String { german ? "Keine Termine bekannt." : "No dates known yet." }
    static func plusOne(_ german: Bool, title: String) -> String { german ? "Eins weiter: \(title)" : "One more: \(title)" }
    static func caughtUp(_ german: Bool) -> String { german ? "Auf dem neuesten Stand" : "Caught up" }
    static func queued(_ german: Bool) -> String { german ? "Wird in Kuro gespeichert" : "Saving in Kuro" }
}

/// Wraps `content` in a `Link` when the row has a deep link (navigation only).
struct WidgetLinked<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let url { Link(destination: url, label: content) } else { content() }
    }
}

/// A cached cover from the snapshot's `thumbs/` directory (never fetched by the widget).
struct WidgetThumbnail: View {
    let name: String?

    var body: some View {
        Group {
            if let name, let url = WidgetSnapshotStore.shared()?.thumbnailURL(named: name),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                WidgetPalette.ink.opacity(0.08)
            }
        }
        .frame(width: 34, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct NextReleaseWidgetView: View {
    let entry: KuroWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int { family == .systemLarge ? 5 : (family == .systemMedium ? 2 : 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WidgetChrome.upNext(entry.german))
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(WidgetPalette.muted)
                .accessibilityAddTraits(.isHeader)
            if entry.snapshot == nil {
                Text(WidgetChrome.signedOut(entry.german)).font(.system(size: 13)).foregroundStyle(WidgetPalette.ink)
            } else if entry.releases.isEmpty {
                Text(WidgetChrome.nothingScheduled(entry.german)).font(.system(size: 13)).foregroundStyle(WidgetPalette.ink)
            } else {
                ForEach(entry.releases.prefix(limit)) { item in
                    WidgetLinked(url: item.deepLink) {
                        HStack(spacing: 8) {
                            if family != .systemSmall { WidgetThumbnail(name: item.thumbnail) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text(item.line).font(.system(size: 12)).foregroundStyle(WidgetPalette.muted).lineLimit(2)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.title), \(item.accessibilityLine)")
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(WidgetPalette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NowWatchingWidgetView: View {
    let entry: KuroWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int { family == .systemLarge ? 4 : (family == .systemMedium ? 2 : 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WidgetChrome.nowWatching(entry.german))
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(WidgetPalette.muted)
                .accessibilityAddTraits(.isHeader)
            if entry.nowWatching.isEmpty {
                Text(WidgetChrome.signedOut(entry.german)).font(.system(size: 13))
            } else {
                ForEach(entry.nowWatching.prefix(limit)) { item in
                    HStack(spacing: 8) {
                        WidgetLinked(url: item.deepLink) {
                            HStack(spacing: 8) {
                                if family != .systemSmall { WidgetThumbnail(name: item.thumbnail) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                    Text(item.isCaughtUp ? WidgetChrome.caughtUp(entry.german) : item.progressText)
                                        .font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(WidgetPalette.muted)
                                }
                            }
                        }
                        Spacer(minLength: 4)
                        if !item.isCaughtUp {
                            Button(intent: AdvanceProgressIntent(item: item)) {
                                Text("+1").font(.system(size: 15, weight: .bold)).frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(WidgetChrome.plusOne(entry.german, title: item.title))
                            .accessibilityValue(item.isQueued ? WidgetChrome.queued(entry.german) : item.progressText)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(WidgetPalette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
