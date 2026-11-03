import SwiftUI

// MARK: - The One Thing (Discover P1; cover story since the Discover + Clubs redesign, 2026-11-03)
// One boosted title per day as the Discover lead: since the redesign (§6.2 item 3) it is the cover
// story, `DiscoverCoverStory`, on the title's own artwork material with the Plan key. No score or
// genre (rulebook §14.5). Tap routes to the standard detail. These wrappers keep the shipped names.

struct DiscoverOneThingCard: View {
    let feature: DailyFeature
    let width: CGFloat
    /// Kicker (default: today's pick; Stage 4 Hidden Gem overrides).
    var eyebrow: String? = nil

    static var defaultEyebrow: String { KuroLocale.text("Today's pick", "Tipp des Tages") }

    var body: some View {
        DiscoverCoverStory(story: DiscoverStory(feature: feature, eyebrow: eyebrow ?? Self.defaultEyebrow),
                           kind: eyebrow == nil ? .lead : .gem, column: width)
    }
}

// MARK: - Skeleton (stable geometry while the daily feature RPC is in flight)
struct DiscoverOneThingSkeleton: View {
    let width: CGFloat

    var body: some View {
        DiscoverStorySkeleton(column: width)
    }
}
