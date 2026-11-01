import SwiftUI

// MARK: - The One Thing (Discover P1, issue frame since 2026-11-01)
// One boosted title per day as the Discover lead frame (spec D8, rulebook §14.5): the full-width
// picture, then a kicker, the serif title and its argument in at most two lines on the white page.
// No glass, no gradient, no score or genre in the frame. Banner art keeps a wide crop; a cover is
// cropped from the top. Tap routes to the standard detail.

struct DiscoverOneThingCard: View {
    let feature: DailyFeature
    let width: CGFloat
    /// Kicker (default: today's pick; Stage 4 Hidden Gem overrides).
    var eyebrow: String? = nil

    static var defaultEyebrow: String { KuroLocale.text("Today's pick", "Tipp des Tages") }

    var body: some View {
        DiscoverLeadFrame(
            kicker: eyebrow ?? Self.defaultEyebrow,
            title: feature.title,
            line: feature.argument,
            imageURL: feature.artURL,
            isWideArt: !(feature.bannerImage ?? "").isEmpty,
            route: MediaRoute(kind: feature.kind, id: feature.mediaId),
            width: width
        )
    }
}

// MARK: - Skeleton (stable geometry while the daily feature RPC is in flight)
struct DiscoverOneThingSkeleton: View {
    let width: CGFloat

    var body: some View {
        DiscoverLeadSkeleton(width: width)
    }
}
