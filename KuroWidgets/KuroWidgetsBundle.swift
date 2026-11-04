import KuroWidgetSupport
import SwiftUI
import WidgetKit

// MARK: - KuroWidgets extension entry point
// Two widgets over the one app-written snapshot (`KuroSnapshotProvider`): the next releases of the
// account's tracked titles, and Now Watching with an interactive +1 (`AdvanceProgressIntent`).
// Gallery names and descriptions are EN/DE from the device language (`WidgetCopy`; the extension has
// no string catalog).

@main
struct KuroWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextReleaseWidget()
        NowWatchingWidget()
    }
}

struct NextReleaseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: KuroAppGroup.WidgetKind.nextRelease, provider: KuroSnapshotProvider()) { entry in
            NextReleaseWidgetView(entry: entry)
                .containerBackground(WidgetPalette.canvas, for: .widget)
        }
        .configurationDisplayName(WidgetCopy.upNext(WidgetCopy.preferredGerman()))
        .description(WidgetCopy.upNextDescription(WidgetCopy.preferredGerman()))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NowWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: KuroAppGroup.WidgetKind.nowWatching, provider: KuroSnapshotProvider()) { entry in
            NowWatchingWidgetView(entry: entry)
                .containerBackground(WidgetPalette.canvas, for: .widget)
        }
        .configurationDisplayName(WidgetCopy.nowWatching(WidgetCopy.preferredGerman()))
        .description(WidgetCopy.nowWatchingDescription(WidgetCopy.preferredGerman()))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
