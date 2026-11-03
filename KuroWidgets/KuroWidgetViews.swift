import AppIntents
import KuroWidgetSupport
import SwiftUI
import WidgetKit

// MARK: - Widget views (thin wrappers; spec §10.4, D22)
// The content lives in `KuroWidgetViews/` (compiled into the app and this extension, so KuroTests
// render it). These wrappers only read the timeline entry and pass the one interactive +1:
// `Button(intent: AdvanceProgressIntent(item:))` around `WidgetKeyFace`. A +1 is never a URL; rows link
// to the title journey only (spec D13, N10).

struct NextReleaseWidgetView: View {
    let entry: KuroWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        NextReleaseWidgetContent(snapshot: entry.snapshot, date: entry.date, family: family, german: entry.german)
    }
}

struct NowWatchingWidgetView: View {
    let entry: KuroWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        NowWatchingWidgetContent(snapshot: entry.snapshot, date: entry.date, family: family,
                                 german: entry.german) { item in
            Button(intent: AdvanceProgressIntent(item: item)) {
                WidgetKeyFace(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}
