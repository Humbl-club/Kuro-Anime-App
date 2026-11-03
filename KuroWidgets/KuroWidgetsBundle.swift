import KuroWidgetSupport
import SwiftUI
import WidgetKit

// MARK: - KuroWidgets extension entry point
// Two widgets over the one app-written snapshot (`KuroSnapshotProvider`): the next releases of the
// account's tracked titles, and Now Watching with an interactive +1 (`AdvanceProgressIntent`).

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
        .configurationDisplayName("Up next")
        .description("The next episodes and chapters of what you follow.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NowWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: KuroAppGroup.WidgetKind.nowWatching, provider: KuroSnapshotProvider()) { entry in
            NowWatchingWidgetView(entry: entry)
                .containerBackground(WidgetPalette.canvas, for: .widget)
        }
        .configurationDisplayName("Now watching")
        .description("What you are watching and reading, with +1.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
