import SwiftUI

// MARK: - Release line (spec §3.5, D10)
// One release row in certainty copy: "Ep. 7 · Thu 15 Oct, 18:30" (confirmed), "Vol. 115 · November"
// (announced), "Ch. 1197 · expected around Sun 9 Nov" (estimated). The wording carries the
// certainty; colour never does. The row's `release_precision` decides the date shape and a time is
// shown only for an instant (day "Thu 15 Oct", month "November", quarter "Q1 2027", year "2027";
// spec §3.3a, see `ReleaseCopy`). German readers get de_DE and Europe/Berlin.
// A row that may not be shown (an estimate below 0.7) renders nothing, and so does an upcoming row
// whose moment has passed since it was read: it never reads as upcoming in confirmed wording
// (only a server-flagged `isPast` row renders, as "released …").

struct KuroReleaseLine: View {
    let item: ReleaseScheduleItem
    /// Adds "via AniList" (or the row's source) on a second line, for detail pages.
    var showsSource: Bool = false
    /// Writes "Dates to come." after the unit when the row has no date (only where the slot would
    /// otherwise be empty).
    var undatedFallback: Bool = false
    var font: Font = .kuroMeta()
    var color: Color = .kuroInkSecondary
    /// The reference time for "today"/"tomorrow" (previews and tests pin it).
    var now: Date = Date()

    init(_ item: ReleaseScheduleItem, showsSource: Bool = false, undatedFallback: Bool = false,
         font: Font = .kuroMeta(), color: Color = .kuroInkSecondary, now: Date = Date()) {
        self.item = item
        self.showsSource = showsSource
        self.undatedFallback = undatedFallback
        self.font = font
        self.color = color
        self.now = now
    }

    var body: some View {
        let copy = ReleaseCopy.current(now: now)
        if item.isDisplayable, item.isPast || copy.isAhead(item) {
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.line(item, undatedFallback: undatedFallback))
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                if showsSource, let source = copy.sourceAttribution(item) {
                    // A licensing credit (D11): readable meta size, not decorative caption.
                    Text(source)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkQuiet)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.accessibilityLine(item))
        }
    }
}
